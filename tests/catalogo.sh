#!/bin/bash
U=${API_URL:-localhost:8000/api}; H='Accept: application/json'; J='Content-Type: application/json'
PW=${SEED_PW:-$(sed -n 's/^SEED_PASS[A-Z]*=//p' backend/.env)}
ok=0; fail=0
chk() { if [ "$2" = "$3" ]; then echo "OK    $1 -> $2"; ok=$((ok+1)); else echo "FALLA $1 -> $2 (esperado $3)"; fail=$((fail+1)); fi; }
req() { curl -s -o /tmp/r.json -w '%{http_code}' -H "$H" -H "$J" -H "Authorization: Bearer $TOK" -X "$1" "$U$2" ${3:+-d "$3"}; }
id() { grep -o '"id":[0-9]*' /tmp/r.json | head -1 | cut -d: -f2; }
login() { curl -s -H "$H" -H "$J" -d "{\"email\":\"$1\",\"password\":\"$PW\"}" $U/login | grep -o '"token":"[^"]*"' | cut -d'"' -f4; }
OP=$(login operador@ecocanje.test); TC=$(login ciudadano1@ecocanje.test); N="Material $(date +%s)"

TOK=$TC
chk "ciudadano no crea materiales"   "$(req POST /materiales "{\"nombre\":\"X\",\"puntos_por_kg\":5}")" 403
TOK=$OP
chk "crear material"                 "$(req POST /materiales "{\"nombre\":\"$N\",\"puntos_por_kg\":9}")" 201; M=$(id)
chk "material duplicado"             "$(req POST /materiales "{\"nombre\":\"$N\",\"puntos_por_kg\":9}")" 422
chk "tarifa fuera de rango"          "$(req POST /materiales/$M/tarifas '{"puntos_por_kg":0}')" 422
chk "nueva tarifa"                   "$(req POST /materiales/$M/tarifas '{"puntos_por_kg":11}')" 201
chk "modificar material"             "$(req PUT /materiales/$M '{"nombre":"'"$N"' editado"}')" 200
chk "ficha MongoDB valida"           "$(req PUT /materiales/$M/ficha '{"atributos":{"color":"transparente","tapa":"si"}}')" 200
chk "ficha con clave invalida"       "$(req PUT /materiales/$M/ficha '{"atributos":{"Mala Clave":"x"}}')" 422
chk "consultar ficha"                "$(req GET /materiales/$M/ficha)" 200
chk "baja logica de material"        "$(req DELETE /materiales/$M)" 204
chk "recompensa valida"              "$(req POST /recompensas '{"nombre":"Vale prueba","tipo":"vale_despensa","costo_puntos":120,"stock":5}')" 201
chk "recompensa tipo invalido"       "$(req POST /recompensas '{"nombre":"X","tipo":"dinero","costo_puntos":1,"stock":1}')" 422
chk "recompensa stock negativo"      "$(req POST /recompensas '{"nombre":"X","tipo":"vale_despensa","costo_puntos":1,"stock":-3}')" 422
TOK=$TC
chk "historial del ciudadano (Mongo)" "$(req GET /historial)" 200
chk "entregas con paginacion"        "$(req GET '/entregas?page=2')" 200
TOK=$OP; NE="Empate $(date +%s%N)"
req POST /materiales "{\"nombre\":\"$NE\",\"puntos_por_kg\":7}" >/dev/null; ME=$(id)
req POST /materiales/$ME/tarifas '{"puntos_por_kg":9}' >/dev/null
req GET /materiales >/dev/null
chk "tarifa cambiada en el mismo segundo: gana la ultima" "$(python3 -c "import json; print([m['puntos_por_kg'] for m in json.load(open('/tmp/r.json')) if m['id']==$ME][0])")" 9
req DELETE /materiales/$ME >/dev/null
echo "Resultado: $ok correctas, $fail fallidas"
exit $((fail>0))
