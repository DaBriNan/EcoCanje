#!/bin/bash
# Uso: scripts/bootstrap.sh            — E14: reconstruye dev y prod desde cero, midiendo cada fase.
#
# Prerrequisitos del host (manual D05; el script los verifica y se detiene si falta alguno):
#   docker, k3d, kubectl, helm, skopeo, mkcert (con su CA creada: mkcert -install), python3 con PyYAML, openssl, bc
#   /etc/hosts:  127.0.0.1 dev.ecocanje.test prod.ecocanje.test
# No borra nada: si un clúster k3d-dev o k3d-prod ya existe, se detiene. Borrarlos es un paso explícito aparte.
# Ningún secreto está en Git: los generan crear-secretos.sh y crear-secretos-monitoreo.sh en cada clúster.
# Imágenes: usa ecocanje-backend y ecocanje-frontend locales si existen (artefactos aprobados); si no, las construye
# desde la revisión actual. En ambos casos la imagen importada se compara con su id aprobado (infra/imagen-aprobada-*).
set -uo pipefail
cd "$(dirname "$0")/.."
BACK=$(sed -n 's/.*ecocanje-backend, newTag: "\([^"]*\)".*/\1/p' infra/prod/kustomization.yaml)
FRONT=$(sed -n 's/.*ecocanje-frontend, newTag: "\([^"]*\)".*/\1/p' infra/prod/kustomization.yaml)
INI=$SECONDS; FASES=(); T=$SECONDS
t() { date '+%T'; }
fase() { local d=$((SECONDS - T)); [ -n "${NOMBRE:-}" ] && FASES+=("$(printf '%-44s %4d s' "$NOMBRE" "$d")"); NOMBRE=$1; T=$SECONDS; echo; echo "$(t) ==== $1"; }
falla() { echo "$(t) ERROR: $*"; resumen; exit 1; }
resumen() { fase fin; echo; echo "Tiempos por fase:"; printf '  %s\n' "${FASES[@]}"; echo "  TOTAL $((SECONDS - INI)) s"; }

fase "0. Prerrequisitos del host"
for b in docker k3d kubectl helm skopeo mkcert python3 openssl bc; do command -v $b >/dev/null || falla "falta $b"; done
python3 -c 'import yaml' || falla "falta PyYAML"
[ -f "$(mkcert -CAROOT)/rootCA.pem" ] || falla "falta la CA de mkcert (mkcert -install)"
for h in dev.ecocanje.test prod.ecocanje.test; do getent hosts $h | grep -q 127.0.0.1 || falla "falta '127.0.0.1 $h' en /etc/hosts"; done
for c in dev prod; do k3d cluster list $c >/dev/null 2>&1 && falla "el clúster $c ya existe; bórralo explícitamente antes (k3d cluster delete $c)"; done
k3d version | head -1; kubectl version --client | head -1; helm version --short; docker --version
echo "versiones a desplegar: backend $BACK, frontend $FRONT, k3s $(cat infra/K3S_VERSION)"
cp docs/manual/gancho-pre-commit.sh .git/hooks/pre-commit && cp docs/manual/gancho-excluir-secretos.txt .git/hooks/excluir-secretos.txt \
  && chmod +x .git/hooks/pre-commit && echo "gancho pre-commit instalado"

fase "1. Imágenes de la aplicación"
REV=$(git rev-parse --short HEAD)
if docker image inspect ecocanje-backend:$BACK >/dev/null 2>&1; then echo "backend $BACK presente (artefacto existente)"
else docker build -q -f backend/Dockerfile.prod --build-arg MONGO_EXT=$(cat infra/MONGODB_EXT_VERSION) --build-arg APP_VERSION=$BACK \
       --label org.opencontainers.image.revision=$REV --label org.opencontainers.image.version=$BACK -t ecocanje-backend:$BACK backend || falla "build backend"; fi
if docker image inspect ecocanje-frontend:$FRONT >/dev/null 2>&1; then echo "frontend $FRONT presente (artefacto existente)"
else docker build -q --build-arg VITE_VERSION=$FRONT --label org.opencontainers.image.revision=$REV \
       --label org.opencontainers.image.version=$FRONT -t ecocanje-frontend:$FRONT frontend || falla "build frontend"; fi

fase "2. Clústeres k3d (dev 1 nodo, prod 1+2)"
scripts/crear-clusters.sh dev || falla "crear dev"
scripts/crear-clusters.sh prod || falla "crear prod"
for c in dev prod; do kubectl --context k3d-$c wait --for=condition=Ready node --all --timeout=180s >/dev/null || falla "nodos de $c"; done
kubectl --context k3d-prod get nodes --no-headers

for ENV in dev prod; do
  fase "3. Imágenes en $ENV (importar y comparar con las aprobadas)"
  k3d image import ecocanje-backend:$BACK ecocanje-frontend:$FRONT -c $ENV 2>&1 | tail -1
  scripts/verificar-imagen.sh $ENV $BACK || falla "imagen backend en $ENV distinta de la aprobada"
  IMG=ecocanje-frontend scripts/verificar-imagen.sh $ENV $FRONT || falla "imagen frontend en $ENV distinta de la aprobada"

  fase "4. Aplicación en $ENV (secretos, TLS, migraciones, despliegue)"
  scripts/desplegar.sh $ENV >/dev/null || falla "desplegar $ENV"
  kubectl --context k3d-$ENV -n ecocanje rollout status deploy/frontend --timeout=180s >/dev/null || falla "frontend $ENV"
  kubectl --context k3d-$ENV -n ecocanje get pods --no-headers
done

fase "5. Observabilidad en prod (métricas, exportadores, alertas, panel)"
kubectl --context k3d-prod apply -f infra/observabilidad/namespaces.yaml >/dev/null
scripts/crear-secretos-monitoreo.sh k3d-prod
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
helm repo update prometheus-community >/dev/null
helm --kube-context k3d-prod upgrade --install kps prometheus-community/kube-prometheus-stack -n monitoring --version 92.17.1 \
  -f infra/observabilidad/kps-values.yaml --wait --timeout 10m >/dev/null || falla "kube-prometheus-stack"
helm --kube-context k3d-prod upgrade --install node-exporter prometheus-community/prometheus-node-exporter -n monitoring-nodos \
  --version 4.60.1 -f infra/observabilidad/node-exporter-values.yaml --wait --timeout 5m >/dev/null || falla "node-exporter"
scripts/observabilidad.sh prod >/dev/null || falla "exportadores y alertas"

fase "6. Logs en prod (Loki y Alloy)"
scripts/logs.sh prod >/dev/null || falla "Loki y Alloy"

fase "7. Verificación final"
source scripts/ev.sh >/dev/null
rc=0
for c in dev prod; do pods_sanos k3d-$c || rc=1; done
for e in "dev 8444" "prod 8445"; do set -- $e
  v=$(curl -s https://$1.ecocanje.test:$2/api/health/live); r=$(curl -s -o /dev/null -w '%{http_code}' https://$1.ecocanje.test:$2/api/health/ready)
  i=$(curl -s -o /dev/null -w '%{http_code}' https://$1.ecocanje.test:$2/)
  echo "$1: live=$v ready=$r interfaz=$i"; [ "$r" = 200 ] && [ "$i" = 200 ] && echo "$v" | grep -q "\"$BACK\"" || rc=1
done
sleep 60   # primer ciclo de scrape de todos los objetivos
scripts/prom.sh prod 'up == 0'; [ $? -eq 2 ] || { echo "hay objetivos caídos en Prometheus"; rc=1; }
scripts/prom.sh prod 'sum(prometheus_rule_group_rules{rule_group=~".*ecocanje.*"}) == 8' || { echo "no estan las 8 reglas de ecocanje"; rc=1; }
scripts/loki.sh prod 'sum by (app) (count_over_time({namespace="ecocanje"}[2m]))' || rc=1
resumen
[ $rc -eq 0 ] && echo "RECONSTRUCCIÓN COMPLETA Y VERIFICADA" || echo "RECONSTRUCCIÓN CON VERIFICACIONES FALLIDAS"
exit $rc
