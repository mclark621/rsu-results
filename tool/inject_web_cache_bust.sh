#!/usr/bin/env bash
# Run after `flutter build web`. Replaces __RSU_CACHE_BUST__ in build/web/index.html
# so each deploy gets a unique flutter_bootstrap.js URL (bypasses disk cache).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INDEX="${ROOT}/build/web/index.html"
if [[ ! -f "${INDEX}" ]]; then
  echo "inject_web_cache_bust: missing ${INDEX} (run flutter build web first)" >&2
  exit 1
fi
SHA="$(git -C "${ROOT}" rev-parse --short HEAD 2>/dev/null || true)"
if [[ -z "${SHA}" ]]; then
  SHA="x"
fi
# Unique per deploy (same commit redeployed still gets a new bootstrap URL).
BUST="v=${SHA}-$(date +%s)"
if [[ "${OSTYPE:-}" == darwin* ]]; then
  sed -i '' "s/__RSU_CACHE_BUST__/${BUST}/g" "${INDEX}"
else
  sed -i "s/__RSU_CACHE_BUST__/${BUST}/g" "${INDEX}"
fi
echo "inject_web_cache_bust: ${BUST}"
