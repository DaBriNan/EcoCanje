#!/bin/bash
# Uso: scripts/estado-datos.sh <contexto>   (conteos en ambas bases y outbox pendiente; no muestra credenciales)
CTX=${1:?contexto}; K() { kubectl --context "$CTX" -n ecocanje "$@"; }
echo "contexto: $CTX"
K exec postgres-0 -- sh -c 'PGPASSWORD=$(cat /run/secrets/pg/admin) psql -h 127.0.0.1 -U ecocanje_admin -d ecocanje -tA -F" | " -c "select (select count(*) from users), (select count(*) from entregas), (select count(*) from outbox where publicado_en is null)"' | sed 's/^/usuarios | entregas | outbox pendientes: /'
K exec mongo-0 -- sh -c 'mongosh --quiet --host 127.0.0.1 -u ecocanje_app -p "$(cat /run/secrets/mongo/app)" --authenticationDatabase ecocanje --eval "print(\"movimientos en MongoDB: \" + db.getSiblingDB(\"ecocanje\").movimientos.countDocuments({}))"'
