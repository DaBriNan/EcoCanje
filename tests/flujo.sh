#!/bin/bash
U=localhost:8000/api; H='Accept: application/json'; J='Content-Type: application/json'
PW=$(sed -n 's/^SEED_PASS[A-Z]*=//p' backend/.env)
ok=0; fail=0
chk() { if [ "$2" = "$3" ]; then echo "OK    $1 -> $2"; ok=$((ok+1)); else echo "FALLA $1 -> $2 (esperado $3)"; fail=$((fail+1)); fi; }
req() { curl -s -o /tmp/r.json -w '%{http_code}' -H "$H" -H "$J" -H "Authorization: Bearer $TOK" -X "$1" "$U$2" ${3:+-d "$3"}; }
id() { grep -o '"id":[0-9]*' /tmp/r.json | head -1 | cut -d: -f2; }
login() { curl -s -H "$H" -H "$J" -d "{\"email\":\"$1\",\"password\":\"$PW\"}" $U/login | grep -o '"token":"[^"]*"' | cut -d'"' -f4; }
hasta_validada() { chk "pesar $1" "$(req PATCH /entregas/$1/pesar "{\"detalles\":[{\"id\":$2,\"peso_kg\":$3}]}")" 200
                   chk "validar $1" "$(req PATCH /entregas/$1/validar)" 200; }

OP=$(login operador@ecocanje.test)
EM="prueba$(date +%s)@ecocanje.test"
TOK=$(curl -s -H "$H" -H "$J" -d "{\"name\":\"Prueba\",\"email\":\"$EM\",\"password\":\"$PW\"}" $U/registro | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
TC=$TOK; req GET /yo >/dev/null; C=$(id); echo "Ciudadano de prueba id=$C"

TOK=$OP
chk "peso negativo"            "$(req POST /entregas "{\"user_id\":$C,\"detalles\":[{\"material_id\":3,\"peso_kg\":-1}]}")" 422
chk "material duplicado"       "$(req POST /entregas "{\"user_id\":$C,\"detalles\":[{\"material_id\":3,\"peso_kg\":1},{\"material_id\":3,\"peso_kg\":2}]}")" 422
chk "registrar 5 kg aluminio"  "$(req POST /entregas "{\"user_id\":$C,\"detalles\":[{\"material_id\":3,\"peso_kg\":5}]}")" 201
E1=$(id); D1=$(grep -o '"detalles":\[{"id":[0-9]*' /tmp/r.json | grep -o '[0-9]*$')
chk "acreditar sin validar"    "$(req PATCH /entregas/$E1/acreditar)" 409
hasta_validada $E1 $D1 5
chk "acreditar (150 pts)"      "$(req PATCH /entregas/$E1/acreditar)" 200
chk "acreditar de nuevo"       "$(req PATCH /entregas/$E1/acreditar)" 409

chk "registrar 12 kg aluminio" "$(req POST /entregas "{\"user_id\":$C,\"detalles\":[{\"material_id\":3,\"peso_kg\":12}]}")" 201
E2=$(id); D2=$(grep -o '"detalles":\[{"id":[0-9]*' /tmp/r.json | grep -o '[0-9]*$')
hasta_validada $E2 $D2 12
chk "tope diario (150+360>500)" "$(req PATCH /entregas/$E2/acreditar)" 422
chk "rechazar con motivo"      "$(req PATCH /entregas/$E2/rechazar '{"motivo":"Excede tope diario"}')" 200

TOK=$TC
chk "ciudadano no registra entregas" "$(req POST /entregas "{\"user_id\":$C,\"detalles\":[{\"material_id\":3,\"peso_kg\":1}]}")" 403
req GET /saldo >/dev/null; echo "saldo: $(cat /tmp/r.json)"
chk "canje saldo insuficiente (500)" "$(req POST /canjes '{"recompensa_id":3}')" 422
chk "canje vale 150"           "$(req POST /canjes '{"recompensa_id":4}')" 201
K=$(id)
chk "segundo canje sin saldo"  "$(req POST /canjes '{"recompensa_id":4}')" 422
TOK=$OP
chk "aprobar canje"            "$(req PATCH /canjes/$K/aprobar)" 200
chk "cancelar canje aprobado"  "$(req PATCH /canjes/$K/cancelar)" 200
chk "entregar canje cancelado" "$(req PATCH /canjes/$K/entregar)" 409
TOK=$TC; req GET /saldo >/dev/null; echo "saldo tras cancelar: $(cat /tmp/r.json)"
chk "canje otra vez (puntos devueltos)" "$(req POST /canjes '{"recompensa_id":4}')" 201
TOK=$OP
chk "reporte mensual"          "$(req GET /reportes/mensual)" 200
echo "Resultado: $ok correctas, $fail fallidas"
exit $((fail>0))
