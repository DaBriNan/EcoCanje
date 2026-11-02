#!/bin/bash
U=${API_URL:-localhost:8000/api}; H='Accept: application/json'; J='Content-Type: application/json'
PW=$(sed -n 's/^SEED_PASS[A-Z]*=//p' backend/.env); fail=0
tok() { curl -s -H "$H" -H "$J" -d "{\"email\":\"$1\",\"password\":\"$PW\"}" $U/login | grep -o '"token":"[^"]*"' | cut -d'"' -f4; }
chk() { [ "$2" = "$3" ] && echo "OK    $1 -> $2" || { echo "FALLA $1 -> $2 (esperado $3)"; fail=1; }; }
code() { curl -s -o /dev/null -w '%{http_code}' -H "$H" "$@"; }
chk "operador en ruta de operador"  "$(code -H "Authorization: Bearer $(tok operador@ecocanje.test)" $U/operador/ping)" 200
chk "credenciales invalidas"        "$(code -H "$J" -d '{"email":"x@x.com","password":"mal"}' $U/login)" 401
chk "ciudadano en ruta de operador" "$(code -H "Authorization: Bearer $(tok ciudadano1@ecocanje.test)" $U/operador/ping)" 403
chk "sin token"                     "$(code $U/operador/ping)" 401
echo "Resultado: $([ $fail -eq 0 ] && echo todas correctas || echo hay fallos)"
exit $fail
