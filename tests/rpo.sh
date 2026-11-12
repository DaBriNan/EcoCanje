#!/bin/bash
# Uso: tests/rpo.sh <dev|prod>  — demuestra la perdida real de datos entre el ultimo respaldo y un fallo (RPO)
ENV=${1:?dev|prod}; CTX=k3d-$ENV; PORT=$([ "$ENV" = dev ] && echo 8444 || echo 8445); API=https://$ENV.ecocanje.test:$PORT/api
[ "$ENV" = prod ] && [ "${PERMITIR_DATOS_EN_PROD:-}" != 1 ] && { echo "crea un material marcador; en prod requiere PERMITIR_DATOS_EN_PROD=1"; exit 2; }
H='Accept: application/json'; J='Content-Type: application/json'; ok=0; fail=0
chk() { if [ "$2" = "$3" ]; then echo "OK    $1 -> $2"; ok=$((ok+1)); else echo "FALLA $1 -> $2 (esperado $3)"; fail=$((fail+1)); fi; }
cnt() { kubectl --context "$CTX" -n "$1" exec -i postgres-0 -- sh -c 'PGPASSWORD=$(cat /run/secrets/pg/admin) psql -h 127.0.0.1 -U ecocanje_admin -d ecocanje -tA -f -' <<<"select count(*) from materiales where nombre='$2';"; }
PW=$(kubectl --context "$CTX" -n ecocanje get secret app-migracion -o jsonpath='{.data.seed-pass}' | base64 -d)

echo "== 1. Respaldo fresco exportado"; scripts/respaldar.sh "$ENV" >/dev/null && scripts/exportar-respaldos.sh "$ENV" >/dev/null || { echo "FALLA el respaldo"; exit 1; }
TB=$(date +%s); echo "respaldo completado a las $(date +%T)"
echo "== 2. Se escribe un dato DESPUES del respaldo"
TOK=$(curl -s -H "$H" -H "$J" -d "{\"email\":\"operador@ecocanje.test\",\"password\":\"$PW\"}" $API/login | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
N="RPO-marcador-$(date +%s)"
chk "marcador creado en el origen" "$(curl -s -o /tmp/m.json -w '%{http_code}' -H "$H" -H "$J" -H "Authorization: Bearer $TOK" -d "{\"nombre\":\"$N\",\"puntos_por_kg\":2}" $API/materiales)" 201
MID=$(grep -o '"id":[0-9]*' /tmp/m.json | head -1 | cut -d: -f2); TM=$(date +%s)
echo "== 3. Se simula el desastre: se restaura desde la copia (espera 61 s por el limite de intentos de login)"; sleep 61
scripts/restaurar.sh "$ENV" > /tmp/rest.out 2>&1; grep -E "RTO medido|FALLA PostgreSQL|dif PG" /tmp/rest.out
echo "== 4. Comparacion"
chk "el marcador existe en el origen" "$(cnt ecocanje "$N")" 1
chk "el marcador NO esta en los datos restaurados (dato perdido)" "$(cnt recuperacion "$N")" 0
chk "la aplicacion sobre los datos restaurados responde" "$(grep -c 'OK    la aplicacion responde' /tmp/rest.out)" 1
echo "ventana de perdida: el dato se escribio $(( TM - TB )) s despues del respaldo; con respaldos diarios la perdida maxima es 24 h (RPO objetivo 86400 s)"
curl -s -o /dev/null -X DELETE -H "$H" -H "Authorization: Bearer $TOK" $API/materiales/$MID
echo "Resultado: $ok correctas, $fail fallidas"; exit $((fail>0))
