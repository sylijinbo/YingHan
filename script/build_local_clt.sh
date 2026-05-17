#!/usr/bin/env zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="YingHan"
BUNDLE_ID="com.jinboli.inputmethod.yinghan"
BUILD_DIR="/tmp/YingHan-manual"
OBJ_DIR="$BUILD_DIR/obj"
APP="$ROOT/dist/${APP_NAME}.app"

cd "$ROOT"
rm -rf "$OBJ_DIR"
mkdir -p "$OBJ_DIR" "$BUILD_DIR"

COMMON_FLAGS=(
  -fobjc-arc
  -mmacosx-version-min=10.13
  -DCOCOAPODS=1
  -Isrc
  -IPods/FMDB/src/fmdb
  -IPods/GCDWebServer
  -IPods/GCDWebServer/GCDWebServer/Core
  -IPods/GCDWebServer/GCDWebServer/Requests
  -IPods/GCDWebServer/GCDWebServer/Responses
  -IPods/MDCDamerauLevenshtein
  -IPods/MDCDamerauLevenshtein/MDCDamerauLevenshtein
  -IPods/MDCDamerauLevenshtein/MDCDamerauLevenshtein/Algorithms
  -IPods/MDCDamerauLevenshtein/MDCDamerauLevenshtein/Algorithms/Data\ Structures
  -IPods/MDCDamerauLevenshtein/MDCDamerauLevenshtein/Categories
)

for file in \
  src/*.m \
  Pods/FMDB/src/fmdb/*.m \
  Pods/GCDWebServer/GCDWebServer/Core/*.m \
  Pods/GCDWebServer/GCDWebServer/Requests/*.m \
  Pods/GCDWebServer/GCDWebServer/Responses/*.m \
  Pods/MDCDamerauLevenshtein/MDCDamerauLevenshtein/Algorithms/*.m \
  Pods/MDCDamerauLevenshtein/MDCDamerauLevenshtein/Algorithms/Data\ Structures/*.m \
  Pods/MDCDamerauLevenshtein/MDCDamerauLevenshtein/Categories/*.m; do
  clang "${COMMON_FLAGS[@]}" -c "$file" -o "$OBJ_DIR/$(basename "$file").o"
done

for file in src/*.mm; do
  clang++ "${COMMON_FLAGS[@]}" -std=c++17 -c "$file" -o "$OBJ_DIR/$(basename "$file").o"
done

clang++ "$OBJ_DIR"/*.o \
  -framework Cocoa \
  -framework AppKit \
  -framework Carbon \
  -framework InputMethodKit \
  -framework JavaScriptCore \
  -framework WebKit \
  -framework SystemConfiguration \
  -lsqlite3 \
  -lz \
  -o "$BUILD_DIR/$APP_NAME"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
chmod +x "$APP/Contents/MacOS/$APP_NAME"
cp Info.plist "$APP/Contents/Info.plist"
plutil -replace CFBundleIdentifier -string "$BUNDLE_ID" "$APP/Contents/Info.plist"
plutil -replace CFBundleName -string "$APP_NAME" "$APP/Contents/Info.plist"
plutil -replace CFBundleDisplayName -string "$APP_NAME" "$APP/Contents/Info.plist"
plutil -replace CFBundleExecutable -string "$APP_NAME" "$APP/Contents/Info.plist"
plutil -replace InputMethodConnectionName -string "${APP_NAME}_1_Connection" "$APP/Contents/Info.plist"
cp him.icns him.png "$APP/Contents/Resources/"
cp dictionary/words_with_frequency_and_translation_and_ipa.sqlite3 dictionary/pinyin_data.sqlite3 "$APP/Contents/Resources/"
cp dictionary/cedict.json dictionary/phonex_encoded_words.json dictionary/fuzzy_soundex_encoded_words.json "$APP/Contents/Resources/"
cp src/phonex.js "$APP/Contents/Resources/"
cp -R web "$APP/Contents/Resources/"
codesign --force --sign - "$APP"

if [[ "${1:-}" == "--run" ]]; then
  pkill -x "$APP_NAME" 2>/dev/null || true
  /usr/bin/open -n "$APP"
fi

echo "$APP"
