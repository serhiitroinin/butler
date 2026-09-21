#!/bin/bash
# Copies the generated Swift bindings out of the installed harness package.
set -euo pipefail
cd "$(dirname "$0")/.."
package="Sidecar/node_modules/@serhiitroinin/fold-harness"
test -d "$package" || { echo "run bun install in Sidecar/ first" >&2; exit 1; }
mkdir -p Sources/FoldHarnessV1
cp "$package/LICENSE" Sources/FoldHarnessV1/LICENSE
{
  version=$(grep -m1 '"version"' "$package/package.json" | cut -d'"' -f4)
  echo "// Generated data bindings from @serhiitroinin/fold-harness@$version."
  echo "// MIT License, Copyright (c) 2026 Serhii Troinin. See LICENSE in this directory."
  echo "// Refresh with scripts/refresh-bindings.sh. Do not edit."
  cat "$package/bindings/swift/Sources/FoldHarnessV1/FoldHarnessV1.swift"
} > Sources/FoldHarnessV1/FoldHarnessV1.swift
echo "refreshed Sources/FoldHarnessV1/FoldHarnessV1.swift"
