#!/bin/bash
# Uso: scripts/probar.sh <dev|prod> tests/interfaz/correr.sh  — E03 desde la interfaz con un navegador real (Playwright).
# Capturas y registro en docs/evidencias/interfaz/<fecha>-<ambiente>/. Sale con el código de la prueba.
set -uo pipefail
RAIZ=$(cd "$(dirname "$0")/../.." && pwd)
BASE=${API_URL%/api}; HOST=${BASE#https://}; HOST=${HOST%%:*}; ENV=${HOST%%.*}
IMG="mcr.microsoft.com/playwright:v1.64.1-noble@sha256:2f05f8a734509a7b3f26a912639488ee08f58a7b292d14d62271bcff9038768f"
OUT=$RAIZ/docs/evidencias/interfaz/$(date +%Y%m%d-%H%M)-$ENV; mkdir -p "$OUT"
echo "navegador: Chromium de Playwright 1.64.1 ($IMG) | sitio: $BASE"
docker run --rm --network host --add-host "$HOST:127.0.0.1" --user "$(id -u):$(id -g)" -e HOME=/tmp \
  -v "$RAIZ/tests/interfaz:/pruebas:ro" -v "$OUT:/out" -e BASE="$BASE" -e SEED_PW="$SEED_PW" -e OUT=/out \
  "$IMG" sh -c 'cp /pruebas/package.json /pruebas/package-lock.json /pruebas/e03.mjs /tmp/ && cd /tmp \
    && PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 npm ci --no-audit --no-fund --loglevel=error >/dev/null && node e03.mjs' 2>&1 | tee "$OUT/registro.txt"
rc=${PIPESTATUS[0]}; echo "capturas: $(ls "$OUT"/*.png 2>/dev/null | wc -l) en ${OUT#$RAIZ/}"; exit $rc
