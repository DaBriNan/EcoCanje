#!/bin/bash
# Uso: scripts/demo-hpa.sh [usuarios=40] [mantener=2m30s]   — demostración en vivo del autoescalado (HPA) en prod.
# Lanza k6 en segundo plano (sube a <usuarios> en 30 s, sostiene <mantener>, baja en 15 s) y cada 5 s muestra el CPU
# del backend frente al objetivo, las réplicas que pide el HPA, las que existen y en qué nodo está cada una.
# Al terminar la carga sigue mostrando la bajada; Ctrl+C la detiene en cualquier momento (k6 se detiene también).
# Solo lee datos (consultas de catálogo y saldo con un ciudadano semilla); no crea registros.
set -uo pipefail
cd "$(dirname "$0")/.."
VUS=${1:-40}; MANTENER=${2:-2m30s}; K="kubectl --context k3d-prod -n ecocanje"
K6_IMG="grafana/k6:2.2.0@sha256:9bd01d6941fca969cb61bb57d2da5ee9b385fe2aa8881df3798c196564d6ace6"
GEN=k6-demo-$$; LOG=$(mktemp)
fin() { docker rm -f "$GEN" >/dev/null 2>&1; rm -f "$LOG"; echo; echo "demostración terminada"; exit 0; }
trap fin INT TERM

estado() {
  local h p n
  h=$($K get hpa backend -o jsonpath='{.status.currentMetrics[0].resource.current.averageUtilization}|{.spec.metrics[0].resource.target.averageUtilization}|{.status.desiredReplicas}|{.status.currentReplicas}|{.spec.minReplicas}|{.spec.maxReplicas}')
  IFS='|' read -r cpu obj des act min max <<< "$h"
  p=$($K get pods -l app=backend --no-headers 2>/dev/null)
  listos=$(echo "$p" | awk '$2=="2/2" && $3=="Running"' | wc -l)
  n=$($K get pods -l app=backend -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' | sed 's/k3d-prod-//' | sort | uniq -c | awk '{printf "%s:%s ", $2, $1}')
  printf '%s  CPU %3s%% (objetivo %s%%)  réplicas: pedidas %s · existen %s · listas %s  [%s-%s]  %s %s\n' \
    "$(date +%T)" "${cpu:-?}" "$obj" "$des" "$act" "$listos" "$min" "$max" "$n" "$1"
}

echo "== Estado inicial"; $K get hpa backend; echo
echo "== Carga: $VUS usuarios simulados con k6 durante ~$MANTENER (consultas de catálogo, saldo e historial)"
SEED_PW=$($K get secret app-migracion -o jsonpath='{.data.seed-pass}' | base64 -d)
docker run -d --name "$GEN" --network host --cpus 1.5 --user "$(id -u):$(id -g)" \
  -v "$PWD/tests/carga:/scripts:ro" -v "$(mkcert -CAROOT)/rootCA.pem:/ca.pem:ro" \
  -e SSL_CERT_FILE=/ca.pem -e BASE="https://prod.ecocanje.test:8445/api" -e USUARIO=ciudadano1@ecocanje.test \
  -e SEED_PW="$SEED_PW" -e PERFIL=demo -e VUS="$VUS" -e MANTENER="$MANTENER" \
  "$K6_IMG" run --quiet /scripts/escenario.js >/dev/null
unset SEED_PW
echo "   (el HPA revisa el CPU cada 15 s; la primera réplica nueva suele aparecer en 30–60 s)"; echo

maxr=0
while docker ps -q --filter name="$GEN" | grep -q .; do
  estado "| carga activa"; a=$($K get hpa backend -o jsonpath='{.status.currentReplicas}'); [ "${a:-0}" -gt "$maxr" ] && maxr=$a
  sleep 5
done
docker logs "$GEN" > "$LOG" 2>&1; docker rm "$GEN" >/dev/null 2>&1
echo; echo "== Resultado de k6"
grep -E "http_req_duration\.|http_req_failed\.|http_reqs\." "$LOG" | sed 's/^ */   /'
echo "   réplicas máximas durante la carga: $maxr"
echo; echo "== Sin carga: el HPA espera 2 min (estabilización) y quita 1 réplica por minuto hasta 2 (Ctrl+C para terminar)"
min=$($K get hpa backend -o jsonpath='{.spec.minReplicas}')
until [ "$($K get hpa backend -o jsonpath='{.status.currentReplicas}')" = "$min" ]; do estado "| bajando"; sleep 10; done
estado "| de vuelta al mínimo"
fin
