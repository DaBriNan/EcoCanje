#!/bin/bash
# Uso: scripts/crear-tls.sh <contexto> <host>  (certificado de la CA local; las llaves viven fuera del repositorio)
set -euo pipefail
CTX=${1:?contexto}; HOST=${2:?host}; D=$HOME/.local/share/ecocanje-pki
mkdir -p "$D"; chmod 700 "$D"
[ -f "$D/$HOST.pem" ] || mkcert -cert-file "$D/$HOST.pem" -key-file "$D/$HOST-key.pem" "$HOST" >/dev/null 2>&1
kubectl --context "$CTX" -n ecocanje create secret tls tls-ecocanje --cert="$D/$HOST.pem" --key="$D/$HOST-key.pem" \
  --dry-run=client -o yaml | kubectl --context "$CTX" apply -f - >/dev/null
echo "tls-ecocanje aplicado en $CTX para $HOST"
