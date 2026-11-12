#!/bin/bash
# Uso: scripts/probar.sh prod tests/correlacion.sh — una solicitud seguida por su X-Request-Id en nginx, Laravel,
# el worker del outbox (logs en Loki) y el documento en MongoDB.
CTX=k3d-${API_URL#https://}; CTX=${CTX%%.*}; K="kubectl --context $CTX -n ecocanje"
H='Accept: application/json'; J='Content-Type: application/json'; ok=0; fail=0
chk() { if [ "$2" = "$3" ]; then echo "OK    $1 -> $2"; ok=$((ok+1)); else echo "FALLA $1 -> $2 (esperado $3)"; fail=$((fail+1)); fi; }
RID="corr-$(date +%s)-$RANDOM"; echo "X-Request-Id: $RID"
TOK=$(curl -s -H "$H" -H "$J" -d "{\"email\":\"operador@ecocanje.test\",\"password\":\"$SEED_PW\"}" $API_URL/login | python3 -c 'import sys,json; print(json.load(sys.stdin)["token"])')
CI=$(curl -s -H "$H" -H "$J" -d "{\"email\":\"ciudadano1@ecocanje.test\",\"password\":\"$SEED_PW\"}" $API_URL/login | python3 -c 'import sys,json; print(json.load(sys.stdin)["token"])')
UID_C=$(curl -s -H "$H" -H "Authorization: Bearer $CI" $API_URL/yo | python3 -c 'import sys,json; print(json.load(sys.stdin)["id"])')
R=$(curl -s -D /tmp/h-$$ -o /tmp/b-$$ -w '%{http_code}' -H "$H" -H "$J" -H "Authorization: Bearer $TOK" -H "X-Request-Id: $RID" \
     -d "{\"user_id\":$UID_C,\"detalles\":[{\"material_id\":1,\"peso_kg\":1.5}]}" $API_URL/entregas)
E=$(python3 -c "import json; print(json.load(open('/tmp/b-$$'))['id'])"); echo "entrega $E registrada"
chk "POST /entregas" "$R" 201
chk "la respuesta devuelve el mismo X-Request-Id" "$(grep -i '^x-request-id' /tmp/h-$$ | tr -d '\r' | awk '{print $2}')" "$RID"
rm -f /tmp/h-$$ /tmp/b-$$
echo "esperando a que Alloy y Loki ingieran (20 s)"; sleep 20
cuenta() { scripts/loki.sh "${CTX#k3d-}" "$1" 5m 20 2>/dev/null | grep -c "$2"; }
N=$(cuenta "{namespace=\"ecocanje\", app=\"backend\", container=\"nginx\"} |= \"rid=$RID\"" "POST /api/entregas")
chk "Loki: log de acceso de nginx con el rid" "$([ "$N" -ge 1 ] && echo si || echo no)" si
N=$(cuenta "{namespace=\"ecocanje\", app=\"backend\", container=\"php\"} | json | context_request_id=\"$RID\"" "evento registrado")
chk "Loki: Laravel registro el evento con el rid (JSON)" "$([ "$N" -ge 1 ] && echo si || echo no)" si
N=$(cuenta "{namespace=\"ecocanje\", app=\"outbox-worker\"} | json | context_request_id=\"$RID\"" "evento publicado en MongoDB")
chk "Loki: el worker publico el evento con el mismo rid" "$([ "$N" -ge 1 ] && echo si || echo no)" si
D=$($K exec mongo-0 -- sh -c "mongosh --quiet --host 127.0.0.1 -u ecocanje_app -p \"\$(cat /run/secrets/mongo/app)\" --authenticationDatabase ecocanje --eval 'print(db.getSiblingDB(\"ecocanje\").movimientos.countDocuments({\"payload.request_id\": \"$RID\"}))'")
chk "MongoDB: documento con payload.request_id" "$D" 1
echo "consulta en Grafana (Explore, Loki): {namespace=\"ecocanje\"} |= \"$RID\""
echo "Resultado: $ok correctas, $fail fallidas"; exit $((fail>0))
