#!/bin/bash
# Uso: scripts/probar.sh <dev|prod> tests/interfaz/correr.sh  — prueba de interfaz con un navegador real (Playwright).
#   dev:  e03.mjs, flujo completo (crea ciudadano, materiales, recompensas, entregas y canjes de prueba).
#   prod: humo.mjs, solo lectura (no crea datos de negocio). Para correr e03 en prod hay que pedirlo explícitamente:
#         PRUEBA=e03 PERMITIR_DATOS_EN_PROD=1 (los datos de prueba quedan en prod).
#   VERSION_ESPERADA=0.1.5 hace que la prueba de humo verifique la versión del pie de página.
# Capturas y registro en docs/evidencias/interfaz/<fecha>-<ambiente>-<prueba>/. Sale con el código de la prueba.
set -uo pipefail
RAIZ=$(cd "$(dirname "$0")/../.." && pwd)
BASE=${API_URL%/api}; HOST=${BASE#https://}; HOST=${HOST%%:*}; ENV=${HOST%%.*}
[ "$ENV" = prod ] && PRUEBA=${PRUEBA:-humo} || PRUEBA=${PRUEBA:-e03}
if [ "$ENV" = prod ] && [ "$PRUEBA" = e03 ] && [ "${PERMITIR_DATOS_EN_PROD:-}" != 1 ]; then
  echo "e03 crea datos de prueba; en prod se usa humo. Para forzarla: PERMITIR_DATOS_EN_PROD=1"; exit 2
fi
IMG="mcr.microsoft.com/playwright:v1.64.1-noble@sha256:2f05f8a734509a7b3f26a912639488ee08f58a7b292d14d62271bcff9038768f"
OUT=$RAIZ/docs/evidencias/interfaz/$(date +%Y%m%d-%H%M)-$ENV-$PRUEBA; mkdir -p "$OUT"
echo "navegador: Chromium de Playwright 1.64.1 ($IMG) | sitio: $BASE | prueba: $PRUEBA.mjs"
docker run --rm --network host --add-host "$HOST:127.0.0.1" --user "$(id -u):$(id -g)" -e HOME=/tmp \
  -v "$RAIZ/tests/interfaz:/pruebas:ro" -v "$OUT:/out" -e BASE="$BASE" -e SEED_PW="$SEED_PW" -e OUT=/out \
  -e VERSION_ESPERADA="${VERSION_ESPERADA:-}" -e PRUEBA="$PRUEBA" \
  "$IMG" sh -c 'cp /pruebas/package.json /pruebas/package-lock.json /pruebas/*.mjs /tmp/ && cd /tmp \
    && PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 npm ci --no-audit --no-fund --loglevel=error >/dev/null && node "$PRUEBA.mjs"' 2>&1 | tee "$OUT/registro.txt"
rc=${PIPESTATUS[0]}; echo "capturas: $(ls "$OUT"/*.png 2>/dev/null | wc -l) en ${OUT#$RAIZ/}"; exit $rc
