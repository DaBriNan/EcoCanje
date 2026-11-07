#!/bin/bash
# Uso: scripts/promover-frontend.sh <versión>   — construye, analiza, prueba en dev, aprueba y promueve el frontend a prod.
# Cada paso es una compuerta: si Trivy encuentra CRITICAL/HIGH o la prueba de interfaz falla en dev, se detiene sin
# registrar la imagen como aprobada ni tocar prod. La misma imagen (mismo id) llega a prod.
set -euo pipefail
cd "$(dirname "$0")/.."
V=${1:?versión}; IMG=ecocanje-frontend:$V
TRIVY=docker.io/aquasec/trivy:0.76.1@sha256:790fd66d1697395d8693d1acaa1ea702406a20f109b6fc7bac8db623eca6c06c
t() { date '+%T'; }
paso() { echo; echo "$(t) ==== $*"; }

paso "1. Construir $IMG desde $(git rev-parse --short HEAD)"
git diff --quiet -- frontend || { echo "hay cambios sin commit en frontend/"; exit 1; }
docker build -q --build-arg VITE_VERSION="$V" --label org.opencontainers.image.revision="$(git rev-parse --short HEAD)" \
  --label org.opencontainers.image.version="$V" -t "$IMG" frontend

paso "2. Análisis de vulnerabilidades (compuerta: 0 CRITICAL y 0 HIGH)"
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock -v "$HOME/.cache/ecocanje-trivy:/root/.cache" "$TRIVY" \
  image --quiet --image-src docker --scanners vuln --severity CRITICAL,HIGH --exit-code 1 "$IMG" | tail -3

for ENV in dev prod; do
  paso "3. Desplegar en $ENV"
  sed -i "s/{name: ecocanje-frontend, newTag: \"[^\"]*\"}/{name: ecocanje-frontend, newTag: \"$V\"}/" "infra/$ENV/kustomization.yaml"
  k3d image import "$IMG" -c "$ENV" 2>&1 | tail -1
  if [ "$ENV" = dev ]; then IMG=ecocanje-frontend scripts/verificar-imagen.sh dev "$V"
  else IMG=ecocanje-frontend scripts/verificar-imagen.sh prod "$V"; fi   # en prod compara con el id aprobado
  scripts/desplegar.sh "$ENV" >/dev/null
  kubectl --context "k3d-$ENV" -n ecocanje rollout status deploy/frontend --timeout=180s
  # Esperar a que solo queden Pods de la versión nueva (los anteriores atienden durante su preStop)
  until [ "$(kubectl --context "k3d-$ENV" -n ecocanje get pods -l app=frontend -o jsonpath='{range .items[*]}{.spec.containers[0].image}{"\n"}{end}' | sort -u)" = "$IMG" ]; do sleep 2; done

  paso "4. Prueba de interfaz en $ENV (compuerta)"
  scripts/probar.sh "$ENV" tests/interfaz/correr.sh

  if [ "$ENV" = dev ]; then
    paso "5. Registrar $IMG como imagen aprobada"
    IMG=ecocanje-frontend scripts/verificar-imagen.sh dev "$V" --registrar
  fi
done
echo; echo "$(t) $IMG aprobado en dev y promovido a prod"
