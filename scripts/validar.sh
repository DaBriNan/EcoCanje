#!/bin/bash
# Uso: scripts/validar.sh [--imagenes]   — validación automática (local y en CI); no toca ningún clúster.
#   1. Sintaxis de scripts (shellcheck, severidad error)      2. Sintaxis PHP del backend
#   3. Manifiestos: kustomize de dev, prod, observabilidad y recuperación validados con kubeconform (esquemas de
#      Kubernetes y de los CRD de Prometheus Operator)          4. Valores de Helm renderizados con los charts fijados
#   5. Configuración de Alloy (alloy fmt)                     6. Ausencia de secretos versionados
#   --imagenes: además construye las imágenes de backend y frontend (lo que hace la CI en cada cambio)
# Cada herramienta corre en Docker con imagen fijada por digest: el resultado no depende del equipo.
set -uo pipefail
cd "$(dirname "$0")/.."
SHELLCHECK=docker.io/koalaman/shellcheck:v0.11.0@sha256:61862eba1fcf09a484ebcc6feea46f1782532571a34ed51fedf90dd25f925a8d
PHP=docker.io/library/php:8.4.26-cli-alpine@sha256:37c8c64177612b72e7f9d2c00481739c166a3708bea27c1cfd27fea1291d82d1
KUSTOMIZE=registry.k8s.io/kustomize/kustomize:v5.8.3@sha256:429eda4a1c76a7de458d0c4ca3ded9b5d764899ff6bdaeccc1d98b1b6ee873e4
KUBECONFORM=ghcr.io/yannh/kubeconform:v0.8.0@sha256:faffaf43f95aa6425306e1ab8d6fcad72acb9049158f38e574c085ea1ec0f64e
HELM=docker.io/alpine/helm:4.2.4@sha256:76c375eed56144c68d6197c55bc5a4552fb42002190b796729901cbab3ae6e51
ALLOY=docker.io/grafana/alloy:v1.21.1@sha256:4039c971193053a84e53dd9ed3e7d4561c069256b024631cd3498a353ed7ece8
K8S=1.36.0   # misma versión menor que k3s v1.36.1
CRD='https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
ok=0; fail=0
paso() { local n=$1; shift; if out=$("$@" 2>&1); then echo "OK    $n"; ok=$((ok+1)); else echo "FALLA $n"; echo "$out" | tail -25 | sed 's/^/      /'; fail=$((fail+1)); fi; }
dr() { docker run --rm --user "$(id -u):$(id -g)" -v "$PWD:/src:ro" -w /src "$@"; }

paso "shellcheck de scripts y pruebas" dr "$SHELLCHECK" -S error scripts/*.sh tests/*.sh tests/interfaz/correr.sh infra/firewall/aplicar.sh
paso "sintaxis PHP del backend" dr --entrypoint sh "$PHP" -c \
  'find backend/app backend/bootstrap backend/config backend/database backend/routes -name "*.php" -print0 | xargs -0 -n1 php -l >/dev/null'

for k in infra/dev infra/prod infra/observabilidad/prod infra/recuperacion; do
  n=$(echo "$k" | tr / -)
  paso "kustomize build $k" sh -c "docker run --rm -v '$PWD:/src:ro' -w /src '$KUSTOMIZE' build '$k' > '$TMP/$n.yaml'"
  paso "kubeconform $k" dr -v "$TMP:/tmp/m:ro" "$KUBECONFORM" -strict -summary -kubernetes-version "$K8S" \
    -schema-location default -schema-location "$CRD" "/tmp/m/$n.yaml"
done

helm_tpl() {  # helm_tpl <repo-url> <chart> <versión> <values>
  docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -v "$PWD:/src:ro" -w /src --entrypoint sh "$HELM" -c \
    "helm template x $2 --repo $1 --version $3 -f $4 >/dev/null"
}
paso "helm kube-prometheus-stack 92.17.1" helm_tpl https://prometheus-community.github.io/helm-charts kube-prometheus-stack 92.17.1 infra/observabilidad/kps-values.yaml
paso "helm prometheus-node-exporter 4.60.1" helm_tpl https://prometheus-community.github.io/helm-charts prometheus-node-exporter 4.60.1 infra/observabilidad/node-exporter-values.yaml
paso "helm loki 19.1.1" helm_tpl https://grafana-community.github.io/helm-charts loki 19.1.1 infra/observabilidad/loki-values.yaml
paso "helm alloy 1.14.2" helm_tpl https://grafana.github.io/helm-charts alloy 1.14.2 infra/observabilidad/alloy-values.yaml
paso "configuración de Alloy (alloy fmt)" sh -c "python3 -c \"import yaml,sys; sys.stdout.write(yaml.safe_load(open('infra/observabilidad/alloy-values.yaml'))['alloy']['configMap']['content'])\" | docker run --rm -i '$ALLOY' fmt - >/dev/null"

sin_secretos() {
  local f; f=$(git ls-files | grep -E '\.(pem|key|crt|dump|archive|enc)$|(^|/)\.env$|kubeconfig' | grep -v '\.example$')
  [ -z "$f" ] || { echo "archivos sensibles versionados: $f"; return 1; }
  ! git grep -n -I -E 'BEGIN [A-Z ]*PRIVATE KEY|K3S_TOKEN=[A-Za-z0-9]|APP_KEY=base64:[A-Za-z0-9+/]{20}' -- . ':!scripts/validar.sh'
}
paso "sin secretos ni claves versionados" sin_secretos

if [ "${1:-}" = --imagenes ]; then
  paso "build frontend" docker build -q -t ecocanje-frontend:ci frontend
  paso "build backend" docker build -q -f backend/Dockerfile.prod --build-arg MONGO_EXT="$(cat infra/MONGODB_EXT_VERSION)" \
    --build-arg APP_VERSION=ci -t ecocanje-backend:ci backend
fi
echo "Resultado: $ok correctas, $fail fallidas"; exit $((fail>0))
