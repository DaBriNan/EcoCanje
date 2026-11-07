#!/bin/bash
# Uso: scripts/respaldar.sh <dev|prod>  — ejecuta ambos respaldos ahora y espera su resultado
ENV=${1:?dev|prod}; CTX=k3d-$ENV; K() { kubectl --context "$CTX" -n ecocanje "$@"; }; T=$(date +%s); rc=0
for m in postgres mongo; do
  J=manual-$m-$T; K create job $J --from=cronjob/respaldo-$m >/dev/null
  for i in $(seq 1 90); do
    s=$(K get job $J -o jsonpath='{.status.succeeded}'); f=$(K get job $J -o jsonpath='{.status.failed}')
    [ "$s" = 1 ] && { echo "== $m ($((i*3)) s)"; K logs job/$J | grep -E "respaldo_ok|error" ; break; }
    [ -n "$f" ] && [ "$f" -ge 2 ] && { echo "== $m FALLO"; K logs job/$J --tail=15; rc=1; break; }
    sleep 3
  done
  [ "$s" = 1 ] || [ $rc -eq 1 ] || { echo "== $m sin terminar"; rc=1; }
done
exit $rc
