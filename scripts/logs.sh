#!/bin/bash
# Uso: scripts/logs.sh prod — logs centralizados: Loki (monolítico) + Alloy + datasource de Grafana (requiere la pila de métricas)
set -euo pipefail
CTX=k3d-${1:?prod}; D=infra/observabilidad
# Validar la sintaxis de la configuración de Alloy antes de tocar el clúster
python3 -c "import yaml,sys; sys.stdout.write(yaml.safe_load(open('$D/alloy-values.yaml'))['alloy']['configMap']['content'])" \
  | docker run --rm -i grafana/alloy:v1.21.1@sha256:4039c971193053a84e53dd9ed3e7d4561c069256b024631cd3498a353ed7ece8 fmt - >/dev/null
echo "configuración de Alloy válida"
helm repo add grafana-community https://grafana-community.github.io/helm-charts >/dev/null 2>&1 || true
helm repo add grafana https://grafana.github.io/helm-charts >/dev/null 2>&1 || true
helm repo update grafana-community grafana >/dev/null
helm --kube-context "$CTX" upgrade --install loki grafana-community/loki -n monitoring --version 19.1.1 -f $D/loki-values.yaml --wait --timeout 10m
helm --kube-context "$CTX" upgrade --install alloy grafana/alloy -n monitoring --version 1.14.2 -f $D/alloy-values.yaml --wait --timeout 5m
kubectl --context "$CTX" apply -f $D/datasource-loki.yaml
kubectl --context "$CTX" -n monitoring get pods -l 'app.kubernetes.io/name in (loki,alloy)' -o wide
