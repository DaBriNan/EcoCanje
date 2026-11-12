#!/bin/bash
# Uso: scripts/desplegar.sh <dev|prod>   (idempotente; recrea el Job de migraciones)
set -euo pipefail
ENV=${1:?dev|prod}; CTX=k3d-$ENV; K() { kubectl --context "$CTX" -n ecocanje "$@"; }
kubectl --context "$CTX" apply -f infra/base/namespace.yaml >/dev/null
scripts/crear-secretos.sh "$CTX" >/dev/null
scripts/crear-tls.sh "$CTX" "$ENV.ecocanje.test"
K delete job migraciones --ignore-not-found --wait=true
kubectl --context "$CTX" apply -k infra/$ENV
for i in $(seq 1 90); do
  s=$(K get job migraciones -o jsonpath='{.status.succeeded}' 2>/dev/null || true)
  f=$(K get job migraciones -o jsonpath='{.status.conditions[?(@.type=="Failed")].status}' 2>/dev/null || true)
  [ "$s" = 1 ] && break
  [ "$f" = True ] && { echo "El Job de migraciones fallo:"; K logs job/migraciones --all-containers --tail=40; exit 1; }
  sleep 5
done
[ "$s" = 1 ] || { echo "Las migraciones no terminaron a tiempo"; exit 1; }
K logs job/migraciones -c migrar --tail=8
K rollout status deployment/backend --timeout=300s
K rollout status deployment/outbox-worker --timeout=300s
K get pods,svc,ingress
