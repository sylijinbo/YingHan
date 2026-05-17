#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DOCUMENTS_DIR="${HOME}/Documents"
DEST="${DOCUMENTS_DIR}/YingHan"
OLD="${DOCUMENTS_DIR}/hallelujahIM"
TS="$(date +%Y%m%d%H%M%S)"

if [[ -e "$DEST" ]]; then
  mv "$DEST" "${DEST}.before-${TS}"
  echo "Backed up existing ${DEST} to ${DEST}.before-${TS}"
fi

if [[ -e "$OLD" ]]; then
  mv "$OLD" "${OLD}.before-yinghan-rename-${TS}"
  echo "Backed up old ${OLD} to ${OLD}.before-yinghan-rename-${TS}"
fi

ditto "$PROJECT_ROOT" "$DEST"
echo "Exported YingHan project to ${DEST}"
