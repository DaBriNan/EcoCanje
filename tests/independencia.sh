#!/bin/bash
# Uso: tests/independencia.sh — dev y prod no comparten datos, credenciales ni volumenes
H='Accept: application/json'; J='Content-Type: application/json'; ok=0; fail=0
chk() { if [ "$2" = "$3" ]; then echo "OK    $1 -> $2"; ok=$((ok+1)); else echo "FALLA $1 -> $2 (esperado $3)"; fail=$((fail+1)); fi; }
url() { echo https://$1.ecocanje.test:$([ "$1" = dev ] && echo 8444 || echo 8445)/api; }
pw() { kubectl --context k3d-$1 -n ecocanje get secret app-migracion -o jsonpath='{.data.seed-pass}' | base64 -d; }
tok() { curl -s -H "$H" -H "$J" -d "{\"email\":\"operador@ecocanje.test\",\"password\":\"$(pw $1)\"}" "$(url $1)/login" | grep -o '"token":"[^"]*"' | cut -d'"' -f4; }
huella() { kubectl --context k3d-$1 -n ecocanje get secret $2 -o jsonpath="{.data.$3}" | sha256sum | cut -c1-16; }
N="Solo-dev-$(date +%s)"
TD=$(tok dev); TP=$(tok prod)
chk "sesion de operador en dev y en prod" "$([ -n "$TD" ] && [ -n "$TP" ] && echo si || echo no)" si
chk "se crea un material marcador solo en dev" "$(curl -s -o /tmp/m.json -w '%{http_code}' -H "$H" -H "$J" -H "Authorization: Bearer $TD" -d "{\"nombre\":\"$N\",\"puntos_por_kg\":3}" "$(url dev)/materiales")" 201
MID=$(grep -o '"id":[0-9]*' /tmp/m.json | head -1 | cut -d: -f2)
chk "el marcador existe en dev" "$(curl -s -H "$H" -H "Authorization: Bearer $TD" "$(url dev)/materiales" | grep -c "$N")" 1
chk "el marcador NO existe en prod" "$(curl -s -H "$H" -H "Authorization: Bearer $TP" "$(url prod)/materiales" | grep -c "$N")" 0
curl -s -o /dev/null -X DELETE -H "$H" -H "Authorization: Bearer $TD" "$(url dev)/materiales/$MID"
for par in "postgres-credenciales admin" "postgres-credenciales app" "mongo-credenciales app" "app-runtime app-key"; do
  set -- $par
  chk "credencial $1/$2 distinta entre dev y prod" "$([ "$(huella dev $1 $2)" != "$(huella prod $1 $2)" ] && echo distinta || echo IGUAL)" distinta
done
comun=$(comm -12 <(kubectl --context k3d-dev get pv -o name | sort) <(kubectl --context k3d-prod get pv -o name | sort) | wc -l)
chk "volumenes persistentes compartidos entre ambientes" "$comun" 0
chk "servidores de API distintos" "$([ "$(kubectl --context k3d-dev config view --minify -o jsonpath='{.clusters[0].cluster.server}')" != "$(kubectl --context k3d-prod config view --minify -o jsonpath='{.clusters[0].cluster.server}')" ] && echo distintos || echo iguales)" distintos
echo "Resultado: $ok correctas, $fail fallidas"; exit $((fail>0))
