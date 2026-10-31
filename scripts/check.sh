#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

for script in scripts/*.sh; do
    bash -n "$script"
done
python3 -B -m unittest discover -s scripts/tests
git ls-files --cached --others --exclude-standard -z -- \
    Package.swift 'Sources/**/*.swift' 'Tests/**/*.swift' \
    'Packages/**/*.swift' 'extensions/**/*.swift' \
    ':!extensions/capture/Sources/CaptureMac/Vendor/**' \
    | xargs -0 swift format lint --strict
export NSUnbufferedIO=YES
# AppKit suites share the process-wide application/menu/focus state.
swift test --disable-automatic-resolution --no-parallel --jobs "${SWIFT_JOBS:-2}"
