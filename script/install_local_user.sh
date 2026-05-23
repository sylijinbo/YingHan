#!/usr/bin/env zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="YingHan"
APP="$ROOT/dist/${APP_NAME}.app"
INSTALL_DIR="$HOME/Library/Input Methods"
DB_DIR="$HOME/Library/Application Support/YingHan"
REGISTER_TOOL="/tmp/register-yinghan"

if [[ ! -d "$APP" ]]; then
  "$ROOT/script/build_local_clt.sh"
fi

clang -fobjc-arc "$ROOT/Tools/RegisterYingHan.m" -framework Foundation -framework Carbon -o "$REGISTER_TOOL"

pkill -x "$APP_NAME" 2>/dev/null || true
mkdir -p "$INSTALL_DIR"
rm -rf "$INSTALL_DIR/${APP_NAME}.app"
cp -R "$APP" "$INSTALL_DIR/${APP_NAME}.app"
mkdir -p "$DB_DIR"
cp "$INSTALL_DIR/${APP_NAME}.app/Contents/Resources/words_with_frequency_and_translation_and_ipa.sqlite3" "$DB_DIR/"
cp "$INSTALL_DIR/${APP_NAME}.app/Contents/Resources/pinyin_data.sqlite3" "$DB_DIR/"
"$REGISTER_TOOL" "$INSTALL_DIR/${APP_NAME}.app"
killall TextInputMenuAgent 2>/dev/null || true
killall SystemUIServer 2>/dev/null || true

echo "Installed $INSTALL_DIR/${APP_NAME}.app"
echo "Preferences: http://127.0.0.1:62718/index.html"
