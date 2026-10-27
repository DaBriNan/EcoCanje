#!/bin/bash
U=localhost:8000/api; H='Accept: application/json'; J='Content-Type: application/json'
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
DC="docker compose --env-file $RAIZ/.env.compose -f $RAIZ/docker-compose.yml"
PW=$(sed -n 's/^SEED_PASS[A-Z]*=//p' $RAIZ/backend/.env)
TOK=$(curl -s -H "$H" -H "$J" -d "{\"email\":\"operador@ecocanje.test\",\"password\":\"$PW\"}" $U/login | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
pend() { $DC exec -T db psql -U ecocanje -d ecocanje -tAc "select count(*) from outbox where publicado_en is null"; }
docs() { $DC exec -T mongo mongosh --quiet --eval "db.getSiblingDB('ecocanje').movimientos.countDocuments({'payload.entrega_id': $1})"; }
art() { $DC exec -T -u $(id -u):$(id -g) -e HOME=/tmp api php artisan "$@"; }
fail=0

echo "== 0. Se preparan colecciones y se publican los pendientes previos"; art mongo:preparar; art outbox:publicar
echo "== 1. Se detiene MongoDB ($(date +%T))"; $DC stop mongo
echo "== 2. La API sigue aceptando escrituras (PostgreSQL es la fuente de verdad)"
CODE=$(curl -s -o /tmp/r.json -w '%{http_code}' -H "$H" -H "$J" -H "Authorization: Bearer $TOK" -d '{"user_id":2,"detalles":[{"material_id":1,"peso_kg":2}]}' $U/entregas)
E=$(grep -o '"id":[0-9]*' /tmp/r.json | head -1 | cut -d: -f2); echo "POST /entregas -> $CODE (entrega $E)"
[ "$CODE" = 201 ] || fail=1
P1=$(pend); echo "Eventos pendientes en outbox: $P1"; [ "$P1" -ge 1 ] || fail=1
echo "== 3. El publicador falla sin perder el evento"; art outbox:publicar
P2=$(pend); echo "Pendientes tras el fallo: $P2"; [ "$P2" -ge 1 ] || fail=1
echo "== 4. Se levanta MongoDB y se publica ($(date +%T))"; $DC start mongo; sleep 8; art mongo:preparar; art outbox:publicar
P3=$(pend); D1=$(docs $E); echo "Pendientes: $P3 | documentos de la entrega $E en MongoDB: $D1"
[ "$P3" = 0 ] && [ "$D1" = 1 ] || fail=1
echo "== 5. Reintento idempotente: se vuelve a marcar como pendiente y se republica"
$DC exec -T db psql -U ecocanje -d ecocanje -c "update outbox set publicado_en=null, intentos=0 where payload->>'entrega_id'='$E'"
art outbox:publicar
D2=$(docs $E); echo "Documentos de la entrega $E tras el reintento: $D2 (esperado: 1, sin duplicados)"
[ "$D2" = 1 ] || fail=1
echo "Resultado: $([ $fail -eq 0 ] && echo 'recuperacion sin duplicados verificada' || echo 'hay fallos')"
exit $fail
