#!/bin/bash
# One real Claude turn against the demo folder: the engine menu as the account
# reports it, the proposal, Approve, and Undo. It spends a little of the
# signed-in account's allowance. Usage: live-claude.sh [light|dark]
set -euo pipefail
cd "$(dirname "$0")/.."

export BUTLER_DATA="${BUTLER_DATA:-/tmp/butler-live}"
export BUTLER_OFFLINE=""
source scripts/app-session.sh
out="docs/screenshots"
appearance="${1:-light}"
trap 'butler_quit' EXIT

top_level_files() { find .demo/Downloads -maxdepth 1 -type f | wc -l | tr -d ' '; }
listed() {
  python3 - "$1" <<'PY' 2>/dev/null
import json, os, sys
d = json.load(open(os.environ["BUTLER_DATA"] + "/state.json"))
print(len(d["folders"][0].get(sys.argv[1], [])))
PY
}
wait_for() {
  local key="$1" want="$2" limit=$((SECONDS + $3))
  until [ "$(listed "$key")" -ge "$want" ]; do
    pgrep -f "Butler.app/Contents/MacOS" >/dev/null || die "the app died; see $BUTLER_DATA/app.log"
    [ $SECONDS -lt $limit ] || die "timed out waiting for $want $key"
    sleep 2
  done
  sleep 2
}

butler_wait_for_easel
bash scripts/make-demo-folder.sh >/dev/null
rm -rf "$BUTLER_DATA"
mkdir -p "$BUTLER_DATA"
python3 - <<'PY'
import json, os, uuid
choice = {"engineId": "kit:claude", "modelId": "sonnet", "controls": {}}
rules = (
    "Sort my Downloads folder.\n"
    "Put invoices and statements in Invoices/<year>.\n"
    "Put screenshots in Screenshots/<year>.\n"
    "Put installers (.dmg) in Installers.\n"
    "Put archives in Archives.\n"
    "Leave the notes and the to-do list at the top level."
)
json.dump({"settings": {"defaultRules": "", "choice": choice}, "folders": [{
    "id": str(uuid.uuid4()), "path": os.path.abspath(".demo/Downloads"), "rules": rules,
    "choice": choice, "revisions": [], "history": [],
}]}, open(os.environ["BUTLER_DATA"] + "/state.json", "w"), indent=1)
PY

BUTLER_SETTLE=20 butler_launch --appearance "$appearance"
before=$(top_level_files)
butler_capture_engine_menu "$out/engine-menu-live-$appearance.png"
[ "${BUTLER_LIVE_MENU_ONLY:-}" = "1" ] && { butler_quit; trap - EXIT; echo "done (menu only)"; exit 0; }

butler_menu Folder Organise
wait_for revisions 1 300
butler_capture "$out/live-claude.png"
butler_menu Folder "Approve Plan"
wait_for history 1 120
[ "$(top_level_files)" -lt "$before" ] || die "the approved plan moved nothing"
butler_menu Folder "Undo Last Run"
sleep 3
[ "$(top_level_files)" -eq "$before" ] || die "Undo left $(top_level_files) files at the top level, not $before"
echo "live turn: proposed, approved, undone; $before files back at the top level"
butler_quit
trap - EXIT
pgrep -f "Butler.app/Contents/MacOS" >/dev/null && die "an app instance is still running"
pgrep -f "fold-harness-sidecar" >/dev/null && die "a sidecar is still running"
echo "done"
