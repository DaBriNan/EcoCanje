#!/bin/bash
# Uso: scripts/probar.sh <dev|prod> tests/<prueba>.sh   (ejecuta una prueba contra el ambiente por HTTPS)
ENV=${1:?dev|prod}; shift
export API_URL=https://$ENV.ecocanje.test:$([ "$ENV" = dev ] && echo 8444 || echo 8445)/api
export SEED_PW=$(kubectl --context k3d-$ENV -n ecocanje get secret app-migracion -o jsonpath='{.data.seed-pass}' | base64 -d)
exec "$@"
