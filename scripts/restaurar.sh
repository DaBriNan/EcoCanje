#!/bin/bash
# Uso: scripts/restaurar.sh <dev|prod>
# Restaura la copia cifrada mas reciente (fuera del cluster) en el namespace aislado "recuperacion",
# la compara con el origen y mide el tiempo (RTO).
ENV=${1:?dev|prod}; CTX=k3d-$ENV; NS=recuperacion; R=$HOME/ecocanje-respaldos/$ENV
KEY=$HOME/.local/share/ecocanje-pki/respaldo.key; ok=0; fail=0; t0=$(date +%s)
K() { kubectl --context "$CTX" -n "$NS" "$@"; }
O() { kubectl --context "$CTX" -n ecocanje "$@"; }
marca() { echo "[$(( $(date +%s) - t0 )) s] $*"; }
chk() { if [ "$2" = "$3" ]; then echo "OK    $1"; ok=$((ok+1)); else echo "FALLA $1 -> $2 (esperado $3)"; fail=$((fail+1)); fi; }

PG=$(ls -1t "$R"/pg-*.enc 2>/dev/null | head -1); MG=$(ls -1t "$R"/mongo-*.enc 2>/dev/null | head -1)
[ -n "$PG" ] && [ -n "$MG" ] || { echo "No hay respaldos exportados en $R"; exit 1; }
for f in "$PG" "$MG"; do (cd "$R" && sha256sum -c "$(basename "$f").sha256" >/dev/null) || { echo "FALLA integridad de $f"; exit 1; }; done
marca "respaldos: $(basename "$PG") y $(basename "$MG") (SHA-256 verificado)"
b=$(basename "$PG" | sed -E 's/^pg-([0-9]{8})-([0-9]{6}).*/\1 \2/'); d=${b% *}; h=${b#* }
BTS=$(date -u -d "${d:0:4}-${d:4:2}-${d:6:2} ${h:0:2}:${h:2:2}:${h:4:2}" +%s)

# 1. espacio aislado con instancias vacias
kubectl --context "$CTX" delete namespace "$NS" --ignore-not-found --wait=true >/dev/null
kubectl --context "$CTX" create namespace "$NS" >/dev/null
kubectl --context "$CTX" label namespace "$NS" pod-security.kubernetes.io/enforce=restricted pod-security.kubernetes.io/enforce-version=v1.36 ambiente=recuperacion >/dev/null
NS=$NS "$(dirname "$0")/crear-secretos.sh" "$CTX" >/dev/null || { echo "FALLA al crear secretos"; exit 1; }
kubectl --context "$CTX" apply -k infra/recuperacion >/dev/null || { echo "FALLA al aplicar"; exit 1; }
K rollout status statefulset/postgres --timeout=300s >/dev/null && K rollout status statefulset/mongo --timeout=300s >/dev/null || { echo "FALLA: las bases no arrancaron"; exit 1; }
marca "PostgreSQL y MongoDB vacios listos en el namespace $NS"

# 2. restauracion desde la copia cifrada
openssl enc -d -aes-256-cbc -pbkdf2 -in "$PG" -pass file:"$KEY" | K exec -i postgres-0 -- sh -c 'cat > /tmp/r.dump'
K exec postgres-0 -- sh -c 'PGPASSWORD=$(cat /run/secrets/pg/migrador) pg_restore -h 127.0.0.1 -U ecocanje_migrador -d ecocanje --no-owner --no-privileges /tmp/r.dump' 2>&1 | tail -5
marca "PostgreSQL restaurado"
openssl enc -d -aes-256-cbc -pbkdf2 -in "$MG" -pass file:"$KEY" | K exec -i mongo-0 -- sh -c 'cat > /tmp/r.archive'
K exec mongo-0 -- sh -c 'mongorestore --quiet --host 127.0.0.1 -u ecocanje_root -p "$(cat /run/secrets/mongo/root)" --authenticationDatabase admin --archive=/tmp/r.archive --gzip --nsInclude="ecocanje.*" --drop' 2>&1 | tail -3
marca "MongoDB restaurado"

# 3. comparacion con el origen
read -r -d '' SQL <<'EOS'
select 'users='||count(*) from users
union all select 'materiales='||count(*) from materiales
union all select 'tarifas='||count(*) from tarifas
union all select 'entregas='||count(*) from entregas
union all select 'entrega_detalles='||count(*) from entrega_detalles
union all select 'recompensas='||count(*) from recompensas
union all select 'canjes='||count(*) from canjes
union all select 'puntos_lotes='||count(*) from puntos_lotes
union all select 'outbox='||count(*) from outbox
union all select 'puntos_restantes='||coalesce(sum(restantes),0) from puntos_lotes
union all select 'llaves_foraneas='||count(*) from pg_constraint where contype='f'
union all select 'restricciones_check='||count(*) from pg_constraint where contype='c' and connamespace='public'::regnamespace
union all select 'indices='||count(*) from pg_indexes where schemaname='public'
union all select 'detalles_huerfanos='||count(*) from entrega_detalles d left join entregas e on e.id=d.entrega_id where e.id is null
union all select 'canjes_huerfanos='||count(*) from canjes c left join recompensas r on r.id=c.recompensa_id where r.id is null;
EOS
read -r -d '' JS <<'EOS'
const d = db.getSiblingDB('ecocanje');
print('movimientos=' + d.movimientos.countDocuments({}));
print('fichas=' + d.fichas_material.countDocuments({}));
print('indices=' + d.movimientos.getIndexes().map(i => i.name).sort().join('|'));
print('validador=' + (d.getCollectionInfos({name: 'movimientos'})[0].options.validator ? 'si' : 'no'));
EOS
pgq() { kubectl --context "$CTX" -n "$1" exec -i postgres-0 -- sh -c 'PGPASSWORD=$(cat /run/secrets/pg/admin) psql -h 127.0.0.1 -U ecocanje_admin -d ecocanje -tA -f -' <<<"$SQL" | sort; }
mq() { kubectl --context "$CTX" -n "$1" exec -i mongo-0 -- sh -c 'cat > /tmp/v.js && mongosh --quiet --host 127.0.0.1 -u ecocanje_root -p "$(cat /run/secrets/mongo/root)" --authenticationDatabase admin --file /tmp/v.js' <<<"$JS" | sort; }
echo "--- PostgreSQL restaurado:"; pgq "$NS"; echo "--- MongoDB restaurado:"; mq "$NS"
chk "PostgreSQL: conteos, relaciones e indices iguales al origen" "$(diff <(pgq ecocanje) <(pgq "$NS") >/dev/null && echo iguales || echo distintos)" iguales
chk "PostgreSQL: sin filas huerfanas tras restaurar" "$(pgq "$NS" | grep -E '^(detalles|canjes)_huerfanos=' | grep -vc '=0$')" 0
chk "MongoDB: documentos, indices y validador iguales al origen" "$(diff <(mq ecocanje) <(mq "$NS") >/dev/null && echo iguales || echo distintos)" iguales
diff <(pgq ecocanje) <(pgq "$NS") | sed 's/^/    dif PG: /'; diff <(mq ecocanje) <(mq "$NS") | sed 's/^/    dif Mongo: /'

# 4. la aplicacion sobre los datos restaurados
K rollout status deployment/backend --timeout=300s >/dev/null || echo "FALLA: el backend no quedo Ready"
K port-forward deploy/backend 18080:8080 >/dev/null 2>&1 & PF=$!; sleep 5
export API_URL=localhost:18080/api SEED_PW=$(O get secret app-migracion -o jsonpath='{.data.seed-pass}' | base64 -d)
chk "la aplicacion responde (ready) sobre la base restaurada" "$(curl -s -o /dev/null -w '%{http_code}' localhost:18080/api/health/ready)" 200
chk "autorizacion por rol con los usuarios restaurados" "$("$(dirname "$0")/../tests/roles.sh" >/tmp/roles.out 2>&1 && echo ok || echo falla)" ok
cat /tmp/roles.out
TOK=$(curl -s -H 'Accept: application/json' -H 'Content-Type: application/json' -d "{\"email\":\"operador@ecocanje.test\",\"password\":\"$SEED_PW\"}" localhost:18080/api/login | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
TOTAL=$(curl -s -H 'Accept: application/json' -H "Authorization: Bearer $TOK" "localhost:18080/api/entregas?page=1" | grep -o '"total":[0-9]*' | head -1 | cut -d: -f2)
chk "la API lista las entregas restauradas" "$TOTAL" "$(pgq "$NS" | sed -n 's/^entregas=//p')"
kill $PF 2>/dev/null
RTO=$(( $(date +%s) - t0 ))
marca "aplicacion funcionando con los datos restaurados"
echo "RTO medido: $RTO s (objetivo 1800 s): $([ $RTO -le 1800 ] && echo CUMPLE || echo NO CUMPLE)"
echo "RPO: antiguedad del respaldo usado: $(( $(date -u +%s) - BTS )) s (objetivo 86400 s); las diferencias contra el origen indican datos escritos despues del respaldo"
echo "El namespace $NS se conserva para inspeccion; para eliminarlo: kubectl --context $CTX delete namespace $NS"
echo "Resultado: $ok correctas, $fail fallidas"; exit $((fail>0))
