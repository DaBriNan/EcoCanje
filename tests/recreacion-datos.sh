#!/bin/bash
# Uso: tests/recreacion-datos.sh <dev|prod>  — E05: se borran los Pods de ambas bases; el StatefulSet los recrea sobre el
# mismo PVC y los datos deben ser idénticos. Condiciones: borrado ordenado (SIGTERM, cierre limpio), sin pérdida del volumen.
ENV=${1:?dev|prod}; K="kubectl --context k3d-$ENV -n ecocanje"; ok=0; fail=0
chk() { if [ -n "$2" ] && [ "$2" = "$3" ]; then echo "OK    $1 -> $2"; ok=$((ok+1)); else echo "FALLA $1 -> $2 (esperado $3)"; fail=$((fail+1)); fi; }
huella_pg() { $K exec postgres-0 -- sh -c 'PGPASSWORD=$(cat /run/secrets/pg/admin) psql -h 127.0.0.1 -U ecocanje_admin -d ecocanje -tA -F/ -c "select (select count(*) from users), (select count(*) from entregas), (select count(*) from entrega_detalles), (select count(*) from canjes), (select coalesce(sum(puntos),0) from puntos_lotes), (select count(*) from outbox)"'; }
huella_mg() { $K exec mongo-0 -- sh -c 'mongosh --quiet --host 127.0.0.1 -u ecocanje_app -p "$(cat /run/secrets/mongo/app)" --authenticationDatabase ecocanje --eval "const d=db.getSiblingDB(\"ecocanje\"); print(d.movimientos.countDocuments({})+\"/\"+d.fichas_material.countDocuments({}))"'; }
recrear() {  # recrear <pod> <statefulset>
  local uid0 uid1 t; uid0=$($K get pod "$1" -o jsonpath='{.metadata.uid}'); t=$(date +%s)
  $K delete pod "$1" --wait=true >/dev/null
  until [ "$($K get pod "$1" -o jsonpath='{.metadata.uid}' 2>/dev/null)" != "" ] && [ "$($K get pod "$1" -o jsonpath='{.metadata.uid}')" != "$uid0" ]; do sleep 1; done
  $K wait --for=condition=Ready "pod/$1" --timeout=180s >/dev/null; uid1=$($K get pod "$1" -o jsonpath='{.metadata.uid}')
  echo "$1 recreado en $(( $(date +%s) - t )) s (Pod nuevo: $([ "$uid0" != "$uid1" ] && echo sí || echo no); PVC $($K get pod "$1" -o jsonpath='{.spec.volumes[?(@.persistentVolumeClaim)].persistentVolumeClaim.claimName}'))"
}
P0=$(huella_pg); M0=$(huella_mg)
echo "antes  PostgreSQL usuarios/entregas/detalles/canjes/suma_puntos/outbox = $P0 | MongoDB movimientos/fichas = $M0"
recrear postgres-0 postgres
recrear mongo-0 mongo
P1=$(huella_pg); M1=$(huella_mg)
echo "después PostgreSQL = $P1 | MongoDB = $M1"
chk "PostgreSQL sin pérdida ni cambios" "$P1" "$P0"
chk "MongoDB sin pérdida ni cambios" "$M1" "$M0"
chk "la aplicación responde tras la recreación" "$(curl -s -o /dev/null -w '%{http_code}' https://$ENV.ecocanje.test:$([ "$ENV" = dev ] && echo 8444 || echo 8445)/api/health/ready)" 200
echo "Resultado: $ok correctas, $fail fallidas"; exit $((fail>0))
