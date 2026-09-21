#!/bin/bash
# Shared helpers for driving one instance of the bundled app.
#
# The app is driven through its menu bar and its launch arguments only. A
# menu-bar path does not change when the view tree does, and clicking a menu
# item needs no keystroke, so it cannot land in another app's window. Every
# osascript call is bounded, and every failure stops the script.

BUTLER_DATA="${BUTLER_DATA:-/tmp/butler-shots}"
BUTLER_AX_TIMEOUT="${BUTLER_AX_TIMEOUT:-20}"

die() { echo "FAILED: $*" >&2; butler_quit; exit 1; }

# macOS has no timeout(1).
bounded() { local seconds="$1"; shift; perl -e 'alarm shift; exec @ARGV' "$seconds" "$@"; }

butler_quit() {
  local attempt
  for attempt in 1 2 3 4 5; do
    pkill -f "Butler.app/Contents/MacOS" 2>/dev/null || true
    pkill -f "fold-harness-sidecar" 2>/dev/null || true
    sleep 1
    pgrep -f "Butler.app/Contents/MacOS" >/dev/null || pgrep -f "fold-harness-sidecar" >/dev/null || return 0
  done
  pkill -9 -f "Butler.app/Contents/MacOS" 2>/dev/null || true
  pkill -9 -f "fold-harness-sidecar" 2>/dev/null || true
  sleep 1
}

# Another agent captures an Electron app on this machine. Its processes are
# never touched; this only waits for them to go, for ten minutes at most.
butler_wait_for_easel() {
  local limit=$((SECONDS + ${BUTLER_EASEL_WAIT:-600})) said=""
  while pgrep -f "easel/node_modules/electron" >/dev/null; do
    [ -n "$said" ] || { echo "waiting for the Easel instance to finish…" >&2; said=1; }
    [ $SECONDS -lt $limit ] || { echo "note: Easel is still up after the wait; going on" >&2; return 0; }
    sleep 10
  done
}

butler_window_id() { swift scripts/window-id.swift Butler | head -1 | cut -d' ' -f1; }
# "x y width height" of the main window, from the window server.
butler_window_frame() { swift scripts/window-id.swift Butler | head -1 | cut -d' ' -f2-; }

butler_launch() {
  mkdir -p "$BUTLER_DATA"
  butler_quit
  BUTLER_OFFLINE="${BUTLER_OFFLINE-1}" \
    BUTLER_OFFLINE_DELAY_MS="${BUTLER_OFFLINE_DELAY_MS:-0}" \
    BUTLER_APPLY_DELAY_MS="${BUTLER_APPLY_DELAY_MS:-0}" \
    BUTLER_DATA_DIR="$BUTLER_DATA" \
    build/Butler.app/Contents/MacOS/Butler --fixed-size "$@" >"$BUTLER_DATA/app.log" 2>&1 &
  local limit=$((SECONDS + 40))
  until [ -n "$(butler_window_id)" ]; do
    pgrep -f "Butler.app/Contents/MacOS" >/dev/null || die "the app exited at launch; see $BUTLER_DATA/app.log"
    [ $SECONDS -lt $limit ] || die "no window after 40 seconds"
    sleep 1
  done
  # The tiling window manager needs a moment to place the new window.
  sleep 3
  butler_resize
  butler_float
  # The sidecar discovers its engines after the window is up.
  sleep "${BUTLER_SETTLE:-10}"
}

butler_front() {
  bounded "$BUTLER_AX_TIMEOUT" osascript -e 'tell application "System Events" to set frontmost of process "Butler" to true' >/dev/null 2>&1 || true
}

# A capture by window id works wherever the window is, but only the key
# window is drawn active. Someone may be using this machine and take the focus
# back, so the capture is checked and taken again until it shows an active
# window.
butler_capture() {
  local id attempt
  for attempt in 1 2 3 4 5 6; do
    butler_front
    sleep 1
    id=$(butler_window_id)
    [ -n "$id" ] || die "no window to capture for $1"
    screencapture -o -x -l "$id" "$1" || die "screencapture failed for $1"
    [ -s "$1" ] || die "$1 is empty"
    if swift scripts/window-active.swift "$1" >/dev/null; then echo "  $1"; return 0; fi
    sleep 3
  done
  die "$1 shows an inactive window after six attempts"
}

butler_open_engine_menu() {
  bounded "$BUTLER_AX_TIMEOUT" osascript >/dev/null 2>&1 <<'APPLESCRIPT'
tell application "System Events" to tell process "Butler"
  set found to false
  repeat with holder in (groups of toolbar 1 of window 1)
    if exists pop up button 1 of holder then
      perform action "AXPress" of pop up button 1 of holder
      set found to true
      exit repeat
    end if
  end repeat
  if not found then error "no menu button in the toolbar"
end tell
APPLESCRIPT
}

# Escape closes an open menu; it goes to Butler only when Butler is in front.
butler_close_menu() {
  local front
  front=$(bounded "$BUTLER_AX_TIMEOUT" osascript -e 'tell application "System Events" to get name of first process whose frontmost is true' 2>/dev/null || echo "")
  [ "$front" = "Butler" ] && bounded "$BUTLER_AX_TIMEOUT" osascript -e 'tell application "System Events" to key code 53' >/dev/null 2>&1
  sleep 1
}

# The window with the engine menu open. A screen region would show whatever
# else is on the screen, another application included, so the window and the
# menu are captured by id and laid together. A menu closes when the focus goes
# elsewhere, so the whole step is tried again.
# Pressing the button blocks until the menu closes again, so the press runs
# in the background and is reaped after the menu is closed.
butler_capture_engine_menu() {
  local attempt press
  for attempt in 1 2 3 4 5; do
    butler_front
    sleep 1
    butler_open_engine_menu & press=$!
    sleep 2
    if swift scripts/menu-composite.swift "$1" Butler 2>/dev/null && [ -s "$1" ] \
      && swift scripts/window-active.swift "$1" >/dev/null; then
      butler_close_menu
      wait "$press" 2>/dev/null || true
      echo "  $1"
      return 0
    fi
    butler_close_menu
    wait "$press" 2>/dev/null || true
    sleep 3
  done
  die "could not capture the engine menu for $1"
}

butler_ax() {
  bounded "$BUTLER_AX_TIMEOUT" osascript -e "tell application \"System Events\" to tell process \"Butler\" to $1" 2>&1 \
    || die "accessibility call failed or timed out: $1"
}

# Clicks an enabled menu-bar item, waiting for it to become enabled first.
butler_menu() {
  local menu="$1" item="$2" limit=$((SECONDS + ${3:-30})) enabled
  while :; do
    enabled=$(bounded "$BUTLER_AX_TIMEOUT" osascript -e "tell application \"System Events\" to tell process \"Butler\" to get enabled of menu item \"$item\" of menu 1 of menu bar item \"$menu\" of menu bar 1" 2>/dev/null || echo "missing")
    [ "$enabled" = "true" ] && break
    [ $SECONDS -lt $limit ] || die "menu item $menu > $item never became enabled (last: $enabled)"
    sleep 1
  done
  butler_ax "click menu item \"$item\" of menu 1 of menu bar item \"$menu\" of menu bar 1" >/dev/null
  sleep 1
}

# A tiling window manager (AeroSpace on the author's machine) moves and tries
# to resize every new window. With --fixed-size the app keeps its own size,
# but while the manager keeps trying, the app keeps putting the window back,
# and a menu opened during that fight is pushed off the screen step by step.
# So when the AeroSpace CLI is present, the window is floated once, which
# ends the fight. A machine without it just skips this.
butler_float() {
  command -v aerospace >/dev/null 2>&1 || return 0
  local id
  id=$(butler_window_id)
  bounded 5 aerospace focus --window-id "$id" </dev/null >/dev/null 2>&1 || return 0
  bounded 5 aerospace layout floating </dev/null >/dev/null 2>&1 || true
  sleep 1
}

# The size is read from the window server, and a capture by window id does
# not need the window in front or even on screen.
butler_resize() {
  local limit=$((SECONDS + 30)) frame=""
  while [ $SECONDS -lt $limit ]; do
    frame=$(butler_window_frame)
    case "$frame" in *" 1180 760") return 0 ;; esac
    sleep 1
  done
  die "the window is '$frame', not 1180 by 760"
}
