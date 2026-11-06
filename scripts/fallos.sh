#!/bin/bash
# Uso: scripts/fallos.sh prod <pod|drain|mongo|postgres>   — pruebas de fallo E11 con tiempos e impacto medidos.
# Una sonda HTTPS (cada 0.2 s) registra el efecto en solicitudes. Sale con 1 si la recuperación no ocurre.
set -uo pipefail
ENV=${1:?prod}; CASO=${2:?pod|drain|mongo|postgres}; CTX=k3d-$ENV
K="kubectl --context $CTX -n ecocanje"
URL=https://$ENV.ecocanje.test:8445/api
SONDA=$(mktemp); t() { date '+%T'; }; rc=0

sonda_ini() { ( while :; do echo "$(date +%s.%N | cut -c1-14) $(curl -sk -o /dev/null -m 2 -w '%{http_code}' $URL/${1:-health/live})"; sleep 0.2; done ) > "$SONDA" & SPID=$!; }
sonda_fin() {
  kill $SPID 2>/dev/null; wait $SPID 2>/dev/null
  awk '{n++; if ($2!="200") {f++; if (!ini) ini=$1; fin=$1} else if (ini) {d=fin-ini+0.2; if (d>max) max=d; ini=0}}
       END {if (ini) {d=fin-ini+0.2; if (d>max) max=d}; printf "sonda: %d solicitudes, %d sin 200 (%.1f%%), corte continuo más largo %.1f s\n", n, f, 100*f/n, max}' "$SONDA"
  awk '$2!="200"{c[$2]++} END{for (k in c) printf "  código %s: %d\n", k, c[k]}' "$SONDA"
}
trap 'kill ${SPID:-} 2>/dev/null; rm -f "$SONDA"' EXIT
reinicios() { $K get pods -l app=backend -o jsonpath='{range .items[*]}{.metadata.name}={.status.containerStatuses[*].restartCount} {end}'; }
listos() { $K get deploy backend -o jsonpath='{.status.readyReplicas}'; }
token() { local pw; pw=$($K get secret app-migracion -o jsonpath='{.data.seed-pass}' | base64 -d)
  curl -sk -H 'Content-Type: application/json' -H 'Accept: application/json' -d "{\"email\":\"operador@ecocanje.test\",\"password\":\"$pw\"}" $URL/login | python3 -c 'import sys,json; print(json.load(sys.stdin)["token"])'; }
psql_admin() { $K exec postgres-0 -- sh -c "PGPASSWORD=\$(cat /run/secrets/pg/admin) psql -h 127.0.0.1 -U ecocanje_admin -d ecocanje -tAc \"$1\""; }
mongo_cuenta() { $K exec mongo-0 -- sh -c "mongosh --quiet --host 127.0.0.1 -u ecocanje_app -p \"\$(cat /run/secrets/mongo/app)\" --authenticationDatabase ecocanje --eval 'print(db.getSiblingDB(\"ecocanje\").movimientos.countDocuments({\"payload.entrega_id\": $1}))'"; }

case "$CASO" in
pod)
  echo "$(t) réplicas: $($K get pods -l app=backend -o jsonpath='{range .items[*]}{.metadata.name}@{.spec.nodeName} {end}')"
  V=$($K get pods -l app=backend -o jsonpath='{.items[0].metadata.name}')
  sonda_ini; sleep 5
  echo "$(t) FALLA: borrar $V"; T=$(date +%s.%N)
  $K delete pod "$V" --wait=false
  until [ "$(listos)" = "$($K get deploy backend -o jsonpath='{.spec.replicas}')" ] && ! $K get pod "$V" >/dev/null 2>&1; do sleep 0.5; done
  echo "$(t) réplicas listas de nuevo en $(echo "$(date +%s.%N) - $T" | bc | cut -c1-5) s"
  sleep 5; sonda_fin
  echo "réplicas ahora: $($K get pods -l app=backend -o jsonpath='{range .items[*]}{.metadata.name}@{.spec.nodeName} {end}')"
  ;;
drain)
  N=${NODO:-$($K get pod -l app=backend -o jsonpath='{.items[0].spec.nodeName}')}
  echo "$(t) nodo a mantener: $N"
  echo "pods de ecocanje en $N:"; $K get pods -o wide --no-headers --field-selector spec.nodeName="$N" | awk '{print "  "$1}'
  $K get pdb; sonda_ini; sleep 5
  echo "$(t) MANTENIMIENTO: drain $N (respeta PDB; sin --force ni --disable-eviction)"; T=$(date +%s)
  kubectl --context $CTX drain "$N" --ignore-daemonsets --delete-emptydir-data --timeout=300s 2>&1 | grep -v -e "^WARNING" | tail -15 || rc=1
  echo "$(t) drain terminó en $(( $(date +%s) - T )) s; réplicas listas: $(listos)"
  $K get pods -o jsonpath='{range .items[*]}{"  "}{.metadata.name} {.status.phase} {.spec.nodeName}{"\n"}{end}'
  echo "capacidad del otro nodo:"; kubectl --context $CTX top nodes
  sleep 20
  echo "$(t) uncordon $N"; kubectl --context $CTX uncordon "$N"
  echo "$(t) reequilibrar: el uncordon no mueve pods; rollout restart de backend y frontend"
  $K rollout restart deploy/backend deploy/frontend >/dev/null
  $K rollout status deploy/backend --timeout=180s >/dev/null && $K rollout status deploy/frontend --timeout=180s >/dev/null
  echo "reparto final: $($K get pods -l 'app in (backend,frontend)' --field-selector=status.phase=Running -o jsonpath='{range .items[*]}{.metadata.labels.app}@{.spec.nodeName} {end}')"
  sleep 10; sonda_fin
  kubectl --context $CTX get nodes
  ;;
mongo)
  TOK=$(token); P0=$(psql_admin "select count(*) from outbox where publicado_en is null")
  echo "$(t) outbox pendientes antes: $P0"; sonda_ini; sleep 3
  echo "$(t) FALLA: MongoDB a 0 réplicas"; T=$(date +%s); $K scale statefulset mongo --replicas=0; $K wait --for=delete pod/mongo-0 --timeout=120s
  C=$(curl -sk -o /tmp/r-$$.json -w '%{http_code}' -H 'Accept: application/json' -H 'Content-Type: application/json' -H "Authorization: Bearer $TOK" \
      -d '{"user_id":2,"detalles":[{"material_id":1,"peso_kg":2}]}' $URL/entregas)
  E=$(grep -o '"id":[0-9]*' /tmp/r-$$.json | head -1 | cut -d: -f2); rm -f /tmp/r-$$.json
  echo "$(t) POST /entregas con MongoDB caído -> $C (entrega $E)"; [ "$C" = 201 ] || rc=1
  sleep 20; P1=$(psql_admin "select count(*) from outbox where publicado_en is null"); echo "$(t) outbox pendientes durante la caída: $P1"
  [ "$P1" -gt "$P0" ] || rc=1
  echo "$(t) RECUPERACIÓN: MongoDB a 1 réplica"; $K scale statefulset mongo --replicas=1; $K rollout status statefulset mongo --timeout=180s
  echo "$(t) MongoDB listo tras $(( $(date +%s) - T )) s de caída"
  W=$SECONDS; until [ "$(psql_admin "select count(*) from outbox where publicado_en is null")" = 0 ] || [ $((SECONDS - W)) -gt 180 ]; do sleep 5; done
  P2=$(psql_admin "select count(*) from outbox where publicado_en is null"); D=$(mongo_cuenta "$E")
  echo "$(t) outbox pendientes tras $((SECONDS - W)) s: $P2 | documentos de la entrega $E en MongoDB: $D (esperado 1)"
  [ "$P2" = 0 ] && [ "$D" = 1 ] || rc=1
  sonda_fin
  ;;
postgres)
  R0=$(reinicios); echo "$(t) reinicios antes: $R0"; sonda_ini health/ready; sleep 3
  echo "$(t) FALLA: PostgreSQL a 0 réplicas"; T=$(date +%s); $K scale statefulset postgres --replicas=0; $K wait --for=delete pod/postgres-0 --timeout=120s
  sleep 60; echo "$(t) tras 60 s sin base: réplicas listas=$(listos) | /health/live=$(curl -sk -o /dev/null -w '%{http_code}' $URL/health/live)"
  R1=$(reinicios); echo "reinicios durante la caída: $R1"
  echo "$(t) RECUPERACIÓN: PostgreSQL a 1 réplica"; $K scale statefulset postgres --replicas=1; $K rollout status statefulset postgres --timeout=180s
  until [ "$(listos)" = "$($K get deploy backend -o jsonpath='{.spec.replicas}')" ]; do sleep 2; done
  echo "$(t) backend listo tras $(( $(date +%s) - T )) s desde la caída"
  sleep 5; sonda_fin
  R2=$(reinicios); echo "reinicios después: $R2"
  [ "$R0" = "$R2" ] && echo "la liveness no reinició contenedores" || { echo "hubo reinicios por la caída de la base"; rc=1; }
  ;;
*) echo "caso desconocido"; exit 1;;
esac
exit $rc
