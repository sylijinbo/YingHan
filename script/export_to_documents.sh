#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DOCUMENTS_DIR="${HOME}/Documents"
DEST="${DOCUMENTS_DIR}/YingHan"
TS="$(date +%Y%m%d%H%M%S)"

if [[ -e "$DEST" ]]; then
  mv "$DEST" "${DEST}.before-${TS}"
  echo "Backed up existing ${DEST} to ${DEST}.before-${TS}"
fi

ditto "$PROJECT_ROOT" "$DEST"
echo "Exported YingHan project to ${DEST}"
