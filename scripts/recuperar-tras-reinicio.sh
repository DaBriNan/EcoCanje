#!/bin/bash
# Uso: scripts/recuperar-tras-reinicio.sh   — tras reiniciar el equipo, recupera dev y prod (D08, escenario 3).
# Al arrancar, Docker puede asignar a los agentes de k3d IP distintas a las registradas y k3s se apaga con
# "failed to find interface with specified node ip" (incidentes del 5, 7 y 9 nov). Este script:
#   1. reinicia solo los agentes con ese error,  2. espera los nodos Ready,
#   3. reequilibra backend y frontend si quedaron en un solo worker,  4. verifica la API por HTTPS.
# Sale con 1 si algo queda mal. No borra nada.
set -uo pipefail
cd "$(dirname "$0")/.."
rc=0; t() { date '+%T'; }
for ENV in dev prod; do
  CTX=k3d-$ENV; PUERTO=$([ "$ENV" = dev ] && echo 8444 || echo 8445)
  k3d cluster list "$ENV" >/dev/null 2>&1 || { echo "$(t) $ENV: el clúster no existe"; rc=1; continue; }
  for c in $(docker ps -a --format '{{.Names}}' | grep -E "^k3d-$ENV-(agent|server)-[0-9]+$"); do
    inicio=$(docker inspect -f '{{.State.StartedAt}}' "$c")
    if docker logs --since "$inicio" "$c" 2>&1 | grep -q "failed to find interface with specified node ip"; then
      echo "$(t) $ENV: $c se apagó por IP intercambiada; reiniciando"; docker restart "$c" >/dev/null
    fi
  done
  kubectl --context "$CTX" wait --for=condition=Ready node --all --timeout=180s >/dev/null \
    && echo "$(t) $ENV: nodos Ready" || { echo "$(t) $ENV: hay nodos sin Ready"; kubectl --context "$CTX" get nodes; rc=1; continue; }
  if [ "$ENV" = prod ]; then
    for app in backend frontend; do
      n=$(kubectl --context "$CTX" -n ecocanje get pods -l app=$app --field-selector=status.phase=Running \
          -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' | sort -u | wc -l)
      if [ "$n" -lt 2 ]; then
        echo "$(t) prod: $app en un solo nodo; reequilibrando"
        kubectl --context "$CTX" -n ecocanje rollout restart deploy/$app >/dev/null
        kubectl --context "$CTX" -n ecocanje rollout status deploy/$app --timeout=240s >/dev/null
      fi
    done
  fi
  for i in $(seq 1 36); do
    [ "$(curl -s -m 5 -o /dev/null -w '%{http_code}' https://$ENV.ecocanje.test:$PUERTO/api/health/ready)" = 200 ] && break; sleep 5
  done
  r=$(curl -s -m 5 -o /dev/null -w '%{http_code}' https://$ENV.ecocanje.test:$PUERTO/api/health/ready)
  echo "$(t) $ENV: API ready=$r"; [ "$r" = 200 ] || rc=1
done
[ $rc -eq 0 ] && echo "$(t) dev y prod operando" || echo "$(t) revisar: quedaron problemas (D08)"
exit $rc
