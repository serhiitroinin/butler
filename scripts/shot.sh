#!/bin/bash
# One screenshot: launch the bundled app with the offline engine, capture the
# window, quit the app and its sidecar. One instance at a time, always.
# With --fixed-size the app holds its own size against a tiling window manager.
set -euo pipefail
cd "$(dirname "$0")/.."

source scripts/app-session.sh
trap 'butler_quit' EXIT

out="$1"; shift
butler_wait_for_easel
butler_launch "$@"
butler_capture "$out"
