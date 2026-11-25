#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/swift-cache"
swift build -c release --disable-sandbox --cache-path "$PWD/.build/package-cache" -debug-info-format none
APP="$PWD/dist/Dictation.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Dictation "$APP/Contents/MacOS/Dictation"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/whisper_worker.py "$APP/Contents/Resources/whisper_worker.py"
cp -R Resources/en.lproj Resources/ru.lproj "$APP/Contents/Resources/"
cp -R .build/release/Dictation_DictationCore.bundle "$APP/Contents/Resources/"
codesign --force --sign "${DICTATION_SIGN_IDENTITY:--}" --identifier local.tim.Dictation "$APP"
codesign --verify --strict "$APP"
printf 'Built: %s\n' "$APP"
