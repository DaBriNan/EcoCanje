#!/bin/bash
# Uso: scripts/observabilidad.sh prod  — exportadores, monitores y alertas (requiere la pila ya instalada)
set -euo pipefail
CTX=k3d-${1:?prod}
kubectl --context "$CTX" -n ecocanje get secret mongo-exportador >/dev/null 2>&1 || {
  M=$(kubectl --context "$CTX" -n ecocanje get secret mongo-credenciales -o jsonpath='{.data.monitor}' | base64 -d)
  kubectl --context "$CTX" -n ecocanje create secret generic mongo-exportador \
    --from-literal=uri="mongodb://ecocanje_monitor:${M}@mongo:27017/admin?authSource=admin&serverSelectionTimeoutMS=3000" >/dev/null
  echo "creado mongo-exportador"; }
kubectl --context "$CTX" apply -k infra/observabilidad/prod
kubectl --context "$CTX" -n ecocanje rollout status deployment/exportador-postgres --timeout=180s
kubectl --context "$CTX" -n ecocanje rollout status deployment/exportador-mongo --timeout=180s
