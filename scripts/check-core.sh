#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Resolve the independent consumer against the repository's admitted dependency revisions.
cp Package.resolved Examples/CoreConsumer/Package.resolved
swift build --package-path Examples/CoreConsumer --scratch-path .build/core-consumer \
    --disable-automatic-resolution --jobs "${SWIFT_JOBS:-2}"
.build/core-consumer/debug/CoreConsumer
