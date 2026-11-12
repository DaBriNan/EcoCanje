#!/bin/bash
# Uso: scripts/demo-pod.sh [backend|frontend]   — demostración en vivo de la autorreparación en prod.
# Mientras una sonda pide la página dos veces por segundo, borra UNA réplica y muestra cada segundo cuántas réplicas
# están listas, el estado de cada Pod y cuántas solicitudes salieron bien. Al final resume el tiempo de reposición y
# las solicitudes fallidas. No crea ni borra datos: solo el Pod, que el Deployment repone.
set -uo pipefail
cd "$(dirname "$0")/.."
APP=${1:-backend}; K="kubectl --context k3d-prod -n ecocanje"
URL=https://prod.ecocanje.test:8445/$([ "$APP" = backend ] && echo api/health/ready || echo)
SONDA=$(mktemp); trap 'kill ${SP:-} 2>/dev/null; rm -f "$SONDA"' EXIT

pods() { $K get pods -l app=$APP --no-headers -o custom-columns=N:.metadata.name,L:.status.containerStatuses[*].ready,F:.status.phase,NODO:.spec.nodeName,BORRANDO:.metadata.deletionTimestamp \
  | awk '{l=($2 ~ /false/ || $2=="<none>") ? "no listo" : "listo"; b=($5=="<none>") ? "" : " (terminando)"; sub("k3d-prod-","",$4); printf "%s[%s, %s%s]  ", substr($1, length($1)-4), $4, l, b}'; }
cuenta() { awk -v c="$1" '$1==c' "$SONDA" | wc -l; }

echo "== Réplicas de $APP antes de la prueba"; $K get pods -l app=$APP -o custom-columns=POD:.metadata.name,ESTADO:.status.phase,NODO:.spec.nodeName; echo
( while :; do curl -s -o /dev/null -m 2 -w '%{http_code}\n' "$URL"; sleep 0.5; done ) > "$SONDA" & SP=$!
sleep 3
V=$($K get pods -l app=$APP -o jsonpath='{.items[0].metadata.name}')
echo "== $(date +%T) Borrando el Pod $V (la sonda sigue pidiendo $URL)"
T0=$(date +%s.%N); $K delete pod "$V" --wait=false >/dev/null
DESEADAS=$($K get deploy $APP -o jsonpath='{.spec.replicas}')
while :; do
  L=$($K get deploy $APP -o jsonpath='{.status.readyReplicas}')
  printf '+%4.1fs  listas %s/%s  %s  sonda: %s bien, %s fallas\n' "$(echo "$(date +%s.%N) - $T0" | bc)" "${L:-0}" "$DESEADAS" "$(pods)" "$(cuenta 200)" "$(( $(wc -l < "$SONDA") - $(cuenta 200) ))"
  [ "${L:-0}" = "$DESEADAS" ] && ! $K get pod "$V" >/dev/null 2>&1 && break
  sleep 1
done
T=$(echo "$(date +%s.%N) - $T0" | bc | cut -c1-4); sleep 3; kill $SP 2>/dev/null; wait $SP 2>/dev/null
TOTAL=$(wc -l < "$SONDA"); OK=$(cuenta 200)
echo; echo "== Resultado"
echo "   Pod repuesto y todas las réplicas listas en ${T} s"
echo "   solicitudes durante la prueba: $TOTAL · bien: $OK · fallidas: $((TOTAL - OK))"
$K get pods -l app=$APP -o custom-columns=POD:.metadata.name,ESTADO:.status.phase,NODO:.spec.nodeName,CREADO:.metadata.creationTimestamp
[ $((TOTAL - OK)) -eq 0 ]
