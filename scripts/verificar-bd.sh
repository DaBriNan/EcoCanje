#!/bin/bash
CTX=${1:?contexto}; K() { kubectl --context "$CTX" -n ecocanje "$@"; }; ok=0; fail=0
chk() { if echo "$2" | grep -qi -- "$3"; then echo "OK    $1"; ok=$((ok+1)); else echo "FALLA $1 -> $2"; fail=$((fail+1)); fi; }
pg() { K exec postgres-0 -- sh -c 'PGPASSWORD=$(cat /run/secrets/pg/'"$1"') psql -h 127.0.0.1 -U ecocanje_'"$1"' -d ecocanje -tAc "'"$2"'" 2>&1' 2>&1; }
mg() { K exec mongo-0 -- sh -c 'mongosh --quiet --host 127.0.0.1 -u ecocanje_'"$1"' -p "$(cat /run/secrets/mongo/'"$1"')" --authenticationDatabase '"$2"' --eval "'"$3"'" 2>&1' 2>&1; }

echo "== PostgreSQL: roles"
K exec postgres-0 -- sh -c 'PGPASSWORD=$(cat /run/secrets/pg/admin) psql -h 127.0.0.1 -U ecocanje_admin -d ecocanje -c "\du"'
chk "pg: app conecta con su contrasena"       "$(pg app 'select 1')" '^1$'
chk "pg: app no es superusuario"              "$(pg app "select rolsuper from pg_roles where rolname='ecocanje_app'")" '^f$'
chk "pg: app no puede crear tablas"           "$(pg app 'create table intruso(id int)')" 'permission denied'
chk "pg: migrador crea y borra tablas"        "$(pg migrador 'create table prueba_mig(id int); drop table prueba_mig')" 'DROP TABLE'
chk "pg: backup no puede escribir"            "$(pg backup 'create table intruso(id int)')" 'permission denied'
chk "pg: monitor lee estadisticas"            "$(pg monitor 'select count(*) from pg_stat_activity')" '^[0-9]'
chk "pg: sin contrasena (localhost) rechazada" "$(K exec postgres-0 -- sh -c 'psql -h 127.0.0.1 -U ecocanje_app -d ecocanje -w -tAc "select 1" 2>&1' 2>&1)" 'no password supplied'
chk "pg: sin contrasena (socket) rechazada"    "$(K exec postgres-0 -- sh -c 'psql -U ecocanje_admin -d ecocanje -w -tAc "select 1" 2>&1' 2>&1)" 'no password supplied'

echo "== MongoDB"
chk "mongo: sin credenciales no lee"          "$(K exec mongo-0 -- mongosh --quiet --host 127.0.0.1 --eval "db.getSiblingDB('ecocanje').prueba.find().toArray()" 2>&1)" 'authentication'
chk "mongo: app escribe en su base"           "$(mg app ecocanje "db.getSiblingDB('ecocanje').prueba.insertOne({x:1}).acknowledged")" 'true'
chk "mongo: app no puede modificar colecciones" "$(mg app ecocanje "db.getSiblingDB('ecocanje').runCommand({collMod:'prueba'})")" 'not authorized'
chk "mongo: app no puede crear usuarios"      "$(mg app ecocanje "db.getSiblingDB('admin').createUser({user:'x',pwd:'yyyyyyyy',roles:[]})")" 'not authorized'
chk "mongo: migrador modifica colecciones"    "$(mg migrador ecocanje "db.getSiblingDB('ecocanje').runCommand({collMod:'prueba'}).ok")" '1'
chk "mongo: migrador limpia la prueba"        "$(mg migrador ecocanje "db.getSiblingDB('ecocanje').prueba.drop()")" 'true'
chk "mongo: monitor lee estado del servidor"  "$(mg monitor admin "db.getSiblingDB('admin').runCommand({serverStatus:1}).ok")" '1'
echo "Resultado: $ok correctas, $fail fallidas"; exit $((fail>0))
