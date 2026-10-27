#!/bin/bash
# Uso: tests/flujo.sh  (con la API en localhost:8000 y la semilla cargada)
U=localhost:8000/api; H='Accept: application/json'; J='Content-Type: application/json'
PW=$(sed -n 's/^SEED_PASS[A-Z]*=//p' backend/.env)
ok=0; fail=0
chk() { if [ "$2" = "$3" ]; then echo "OK    $1 -> $2"; ok=$((ok+1)); else echo "FALLA $1 -> $2 (esperado $3)"; fail=$((fail+1)); fi; }
req() { curl -s -o /tmp/r.json -w '%{http_code}' -H "$H" -H "$J" -H "Authorization: Bearer $TOK" -X "$1" "$U$2" ${3:+-d "$3"}; }
id() { grep -o '"id":[0-9]*' /tmp/r.json | head -1 | cut -d: -f2; }

TOK=$(curl -s -H "$H" -H "$J" -d "{\"email\":\"operador@ecocanje.test\",\"password\":\"$PW\"}" $U/login | grep -o '"token":"[^"]*"' | cut -d'"' -f4); OP=$TOK
EM="prueba$(date +%s)@ecocanje.test"
TOKC=$(curl -s -H "$H" -H "$J" -d "{\"name\":\"Prueba\",\"email\":\"$EM\",\"password\":\"$PW\"}" $U/registro | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
TOK=$TOKC; req GET /yo >/dev/null; UID_C=$(id)
echo "Ciudadano de prueba: id=$UID_C"

TOK=$OP
chk "entrega con peso negativo"          "$(req POST /entregas "{\"user_id\":$UID_C,\"detalles\":[{\"material_id\":3,\"peso_kg\":-1}]}")" 422
chk "entrega con material duplicado"     "$(req POST /entregas "{\"user_id\":$UID_C,\"detalles\":[{\"material_id\":3,\"peso_kg\":1},{\"material_id\":3,\"peso_kg\":2}]}")" 422
chk "registrar entrega 5 kg aluminio"    "$(req POST /entregas "{\"user_id\":$UID_C,\"detalles\":[{\"material_id\":3,\"peso_kg\":5}]}")" 201; E1=$(id)
chk "acreditar sin validar (transicion invalida)" "$(req PATCH /entregas/$E1/acreditar)" 409
chk "pesar"                              "$(req PATCH /entregas/$E1/pesar "{\"detalles\":[{\"id\":$(grep -o '"detalles":\[{"id":[0-9]*' /tmp/r.json | grep -o '[0-9]*$' | head -1),\"peso_kg\":5}]}")" 422
