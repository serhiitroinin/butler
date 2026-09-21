#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bun build host.ts --target=node --format=esm --packages=external --outfile=host.mjs
echo "wrote $(pwd)/host.mjs"
