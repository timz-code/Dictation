#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/swift-cache"
swift test --disable-sandbox --cache-path "$PWD/.build/package-cache" -debug-info-format none
python3 -m unittest discover -s scripts -p 'test_*_unit.py'
