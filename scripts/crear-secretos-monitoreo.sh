#!/bin/bash
# Uso: scripts/crear-secretos-monitoreo.sh <contexto>  — crea la credencial de Grafana sin mostrarla
set -euo pipefail
CTX=${1:?contexto}
kubectl --context "$CTX" -n monitoring get secret grafana-admin >/dev/null 2>&1 && { echo "grafana-admin ya existe"; exit 0; }
kubectl --context "$CTX" -n monitoring create secret generic grafana-admin \
  --from-literal=admin-user=admin --from-literal=admin-password="$(openssl rand -base64 24 | tr -d '/+=' | cut -c1-24)" >/dev/null
echo "creado grafana-admin (clave admin-user, admin-password)"
