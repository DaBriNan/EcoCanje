#!/bin/bash
# Uso: scripts/probar.sh prod tests/balanceo.sh [N]  — E07: varias réplicas atienden solicitudes.
# Envía N solicitudes con una marca única y cuenta en el log de nginx de cada Pod cuántas atendió.
# Sale con 1 si menos de 2 réplicas recibieron tráfico.
N=${1:-60}; CTX=k3d-${API_URL#https://}; CTX=${CTX%%.*}; K="kubectl --context $CTX -n ecocanje"
M="e07-$(date +%s)"; DESDE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
echo "réplicas: $($K get pods -l app=backend -o jsonpath='{range .items[*]}{.metadata.name}@{.spec.nodeName} {end}')"
ok=0; for i in $(seq 1 "$N"); do
  c=$(curl -s -o /dev/null -w '%{http_code}' -H 'Connection: close' "$API_URL/health/live?marca=$M-$i"); [ "$c" = 200 ] && ok=$((ok+1))
done
echo "enviadas=$N respuestas_200=$ok marca=$M"; sleep 2
total=0; con=0
for p in $($K get pods -l app=backend -o jsonpath='{.items[*].metadata.name}'); do
  n=$($K logs "$p" -c nginx --since-time="$DESDE" | grep -c "marca=$M-")
  echo "  $p ($($K get pod "$p" -o jsonpath='{.spec.nodeName}')): $n"; total=$((total+n)); [ "$n" -gt 0 ] && con=$((con+1))
done
echo "atendidas en logs=$total, réplicas con tráfico=$con"
[ "$con" -ge 2 ] && [ "$total" -eq "$N" ]
