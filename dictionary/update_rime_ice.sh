#!/bin/sh
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DICT_DIR="$ROOT/dictionary"
REF="${RIME_ICE_REF:-main}"
WORK_DIR="${TMPDIR:-/private/tmp}/yinghan-rime-ice-update"
ARCHIVE="$WORK_DIR/rime-ice.tar.gz"
EXTRACT_DIR="$WORK_DIR/extract"
OUT_DIR="$WORK_DIR/out"
CACHE_DIR="${RIME_ICE_CACHE_DIR:-$HOME/Library/Caches/YingHan/rime-ice}"
CACHE_ROOT="$CACHE_DIR/source"
CACHE_COMMIT_FILE="$CACHE_DIR/COMMIT"
BACKUP_DIR="$DICT_DIR/backups/rime-ice-$(date +%Y%m%d-%H%M%S)"
SOURCE_URL="https://github.com/iDvel/rime-ice"
REFRESH=0

for arg in "$@"; do
  case "$arg" in
    --refresh)
      REFRESH=1
      ;;
    --ref=*)
      REF="${arg#--ref=}"
      REFRESH=1
      ;;
    *)
      echo "Usage: sh dictionary/update_rime_ice.sh [--refresh] [--ref=<commit-or-branch>]" >&2
      exit 2
      ;;
  esac
done

COMMIT=""
RIME_ROOT=""

rm -rf "$WORK_DIR"
mkdir -p "$EXTRACT_DIR" "$OUT_DIR"

if [ "$REFRESH" -eq 0 ] && [ -d "$CACHE_ROOT" ]; then
  RIME_ROOT="$CACHE_ROOT"
  if [ -f "$CACHE_COMMIT_FILE" ]; then
    COMMIT="$(cat "$CACHE_COMMIT_FILE")"
  else
    COMMIT="cached"
  fi
  echo "Using cached rime-ice source: $RIME_ROOT ($COMMIT)"
else
  if command -v git >/dev/null 2>&1; then
    COMMIT="$(git ls-remote "$SOURCE_URL.git" "$REF" | awk '{print $1}' | head -n 1)"
  fi

  if [ -z "$COMMIT" ]; then
    COMMIT="$REF"
  fi

  curl -L -o "$ARCHIVE" "https://github.com/iDvel/rime-ice/archive/${COMMIT}.tar.gz"
  tar -xzf "$ARCHIVE" -C "$EXTRACT_DIR"
  RIME_ROOT="$(find "$EXTRACT_DIR" -mindepth 1 -maxdepth 1 -type d | head -n 1)"

  rm -rf "$CACHE_ROOT"
  mkdir -p "$CACHE_DIR"
  cp -R "$RIME_ROOT" "$CACHE_ROOT"
  echo "$COMMIT" > "$CACHE_COMMIT_FILE"
  RIME_ROOT="$CACHE_ROOT"
  echo "Cached rime-ice source: $RIME_ROOT ($COMMIT)"
fi

python3 "$DICT_DIR/build_rime_ice_pinyin.py" \
  --rime-root "$RIME_ROOT" \
  --sqlite-output "$OUT_DIR/pinyin_data.sqlite3" \
  --frequency-output "$OUT_DIR/rime_ice_frequency.json" \
  --metadata-output "$OUT_DIR/rime_ice_update.json" \
  --source-ref "$REF" \
  --source-commit "$COMMIT"

sqlite3 "$OUT_DIR/pinyin_data.sqlite3" "SELECT COUNT(*) FROM pinyin_data" >/dev/null
python3 - "$OUT_DIR/rime_ice_frequency.json" <<'PY'
import json
import sys

path = sys.argv[1]
data = json.load(open(path, encoding="utf-8"))
missing = [word for word in ("你好", "中国", "测试", "软件") if word not in data]
if missing:
    raise SystemExit("missing frequency samples: " + ", ".join(missing))
PY

mkdir -p "$BACKUP_DIR"
for file in pinyin_data.sqlite3 rime_ice_frequency.json rime_ice_update.json cedict.json; do
  if [ -f "$DICT_DIR/$file" ]; then
    cp "$DICT_DIR/$file" "$BACKUP_DIR/"
  fi
done
if ls "$BACKUP_DIR"/* >/dev/null 2>&1; then
  shasum -a 256 "$BACKUP_DIR"/* > "$BACKUP_DIR/SHA256SUMS.txt"
fi

cp "$OUT_DIR/pinyin_data.sqlite3" "$DICT_DIR/pinyin_data.sqlite3"
cp "$OUT_DIR/rime_ice_frequency.json" "$DICT_DIR/rime_ice_frequency.json"
cp "$OUT_DIR/rime_ice_update.json" "$DICT_DIR/rime_ice_update.json"

echo "Updated rime-ice data from $COMMIT"
echo "Backup: $BACKUP_DIR"
shasum -a 256 "$DICT_DIR/pinyin_data.sqlite3" "$DICT_DIR/rime_ice_frequency.json" "$DICT_DIR/rime_ice_update.json"
