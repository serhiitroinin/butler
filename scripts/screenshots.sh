#!/bin/bash
# Captures every state in both appearances, one app instance at a time, and
# leaves nothing running. Usage: screenshots.sh [light|dark]...
# BUTLER_ONLY=failure captures only the failed apply.
set -euo pipefail
cd "$(dirname "$0")/.."

source scripts/app-session.sh
out="docs/screenshots"
mkdir -p "$out" "$BUTLER_DATA"
locked=".demo/Downloads/invoice-2024-05.pdf"
trap 'butler_quit; chflags nouchg "$locked" 2>/dev/null || true' EXIT

state() {
  python3 - "$1" <<'PY'
import json, os, sys, uuid
choice = {"engineId": "kit:offline", "modelId": "scripted", "controls": {}}
rules = (
    "Sort my Downloads folder.\n"
    "Put invoices and statements in Invoices/<year>.\n"
    "Put screenshots in Screenshots/<year>.\n"
    "Put installers (.dmg) in Installers.\n"
    "Put archives in Archives.\n"
    "Leave the notes and the to-do list at the top level."
)
folders = [] if sys.argv[1] == "empty" else [{
    "id": str(uuid.uuid4()),
    "path": os.path.abspath(".demo/Downloads"),
    "rules": rules,
    "choice": choice,
    "revisions": [],
    "history": [],
}]
json.dump(
    {"settings": {"defaultRules": "", "choice": choice}, "folders": folders},
    open(os.environ.get("BUTLER_DATA", "/tmp/butler-shots") + "/state.json", "w"),
    indent=1,
)
PY
}

# Waits until state.json holds at least N of a list ("revisions", "history").
wait_for() {
  local key="$1" want="$2" limit=$((SECONDS + ${3:-90}))
  until python3 - "$key" "$want" <<'PY' 2>/dev/null
import json, os, sys
d = json.load(open(os.environ.get("BUTLER_DATA", "/tmp/butler-shots") + "/state.json"))
f = d["folders"][0] if d["folders"] else {}
sys.exit(0 if len(f.get(sys.argv[1], [])) >= int(sys.argv[2]) else 1)
PY
  do
    pgrep -f "Butler.app/Contents/MacOS" >/dev/null || die "the app died while waiting for $want $key; see $BUTLER_DATA/app.log"
    [ $SECONDS -lt $limit ] || die "timed out waiting for $want $key"
    sleep 1
  done
  sleep 2
}

capture_smallest_window() {
  sleep 2
  local id
  id=$(swift scripts/panel-window-id.swift | head -1)
  [ -n "$id" ] || die "no second window for $1"
  screencapture -o -x -l "$id" "$1" || die "screencapture failed for $1"
  echo "  $1"
}

top_level_files() { find .demo/Downloads -maxdepth 1 -type f | wc -l | tr -d ' '; }

appearances=("$@")
[ ${#appearances[@]} -gt 0 ] || appearances=(light dark)

for appearance in "${appearances[@]}"; do
  echo "== $appearance"
  butler_wait_for_easel
  bash scripts/make-demo-folder.sh >/dev/null
  if [ "${BUTLER_ONLY:-}" != "failure" ]; then

  state empty
  butler_launch --appearance "$appearance"
  butler_capture "$out/no-folders-$appearance.png"
  butler_quit

  # No proposal, the engine at work, and the proposal it makes.
  state folder
  BUTLER_OFFLINE_DELAY_MS=3000 butler_launch --appearance "$appearance"
  butler_capture "$out/no-proposal-$appearance.png"
  butler_menu Folder Organise
  sleep 3
  butler_capture "$out/working-$appearance.png"
  wait_for revisions 1
  butler_capture "$out/proposal-$appearance.png"
  butler_quit

  # The same proposal as the folder is now and as it would be. The plan is in
  # state.json, so a new instance opens on it.
  for stage in before after; do
    butler_launch --appearance "$appearance" --stage "$stage"
    butler_capture "$out/$stage-$appearance.png"
    butler_quit
  done

  # Exclusions, a change request, its revision, the approve moment, and after.
  butler_wait_for_easel
  state folder
  BUTLER_OFFLINE_DELAY_MS=1500 BUTLER_APPLY_DELAY_MS=140 \
    butler_launch --appearance "$appearance" --select 2 --ask "Put the archives in Attic."
  butler_menu Folder Organise
  wait_for revisions 1
  butler_menu Folder "Exclude Selected"
  butler_capture "$out/excluded-$appearance.png"
  butler_menu Folder "Ask for Changes"
  sleep 1
  butler_capture "$out/change-request-$appearance.png"
  wait_for revisions 2
  butler_capture "$out/revision-$appearance.png"
  butler_capture_engine_menu "$out/engine-menu-$appearance.png"
  butler_menu Folder "Approve Plan"
  sleep 4
  butler_capture "$out/applying-$appearance.png"
  wait_for history 1 60
  butler_capture "$out/applied-$appearance.png"
  butler_menu Go History
  butler_capture "$out/history-$appearance.png"
  butler_menu Go "House Rules"
  butler_capture "$out/house-rules-$appearance.png"
  butler_menu Butler "Settings…"
  capture_smallest_window "$out/settings-$appearance.png"
  butler_quit
  fi

  # An apply that really fails: one file is locked (the user-immutable flag,
  # Finder's "Locked"), so the file system refuses to move it. The applier
  # stops there; Undo then puts back what it had already moved.
  butler_wait_for_easel
  bash scripts/make-demo-folder.sh >/dev/null
  state folder
  butler_launch --appearance "$appearance"
  butler_menu Folder Organise
  wait_for revisions 1
  before=$(top_level_files)
  chflags uchg "$locked"
  butler_menu Folder "Approve Plan"
  wait_for history 1 60
  [ "$(top_level_files)" -lt "$before" ] || die "nothing was moved before the locked file"
  [ -f "$locked" ] || die "the locked file moved"
  butler_capture "$out/apply-failed-$appearance.png"
  butler_menu Folder "Undo Last Run"
  sleep 2
  chflags nouchg "$locked"
  [ "$(top_level_files)" -eq "$before" ] || die "Undo left $(top_level_files) files at the top level, not $before"
  butler_quit
done

trap - EXIT
if pgrep -f "Butler.app/Contents/MacOS" >/dev/null; then die "an app instance is still running"; fi
if pgrep -f "fold-harness-sidecar" >/dev/null; then die "a sidecar is still running"; fi
echo "done"
