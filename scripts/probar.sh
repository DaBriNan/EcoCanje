#!/bin/bash
# Uso: scripts/probar.sh <dev|prod> tests/<prueba>.sh   (ejecuta una prueba contra el ambiente por HTTPS)
ENV=${1:?dev|prod}; shift
# Las pruebas que crean datos de negocio no corren en prod salvo petición explícita (los datos de prueba confunden la
# operación real). La prueba de interfaz decide sola: humo de solo lectura en prod (tests/interfaz/correr.sh).
case "$1" in tests/flujo.sh|tests/catalogo.sh|tests/correlacion.sh)
  if [ "$ENV" = prod ] && [ "${PERMITIR_DATOS_EN_PROD:-}" != 1 ]; then
    echo "$1 crea datos de prueba; en prod requiere PERMITIR_DATOS_EN_PROD=1"; exit 2; fi;; esac
export API_URL=https://$ENV.ecocanje.test:$([ "$ENV" = dev ] && echo 8444 || echo 8445)/api
export SEED_PW=$(kubectl --context k3d-$ENV -n ecocanje get secret app-migracion -o jsonpath='{.data.seed-pass}' | base64 -d)
exec "$@"
