#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

for script in scripts/*.sh; do
    bash -n "$script"
done
git ls-files --cached --others --exclude-standard -z -- \
    Package.swift 'Sources/**/*.swift' 'Tests/**/*.swift' \
    'Packages/**/*.swift' 'extensions/**/*.swift' \
    ':!extensions/capture/Sources/CaptureMac/Vendor/**' \
    | xargs -0 swift format lint --strict
swift test
