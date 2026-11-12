#!/bin/bash
# Uso: tests/exposicion.sh  — E08/D03: la API de los clústeres y la entrada HTTPS solo deben responder en 127.0.0.1.
# Intenta conectar por la IP de cada interfaz externa del host; "alcanzable" en una IP externa es un hallazgo.
ok=0; fail=0
chk() { if [ "$2" = "$3" ]; then echo "OK    $1 -> $2"; ok=$((ok+1)); else echo "FALLA $1 -> $2 (esperado $3)"; fail=$((fail+1)); fi; }
prueba() { curl -sk -o /dev/null -m 3 -w '%{http_code}' "$1" 2>/dev/null | grep -qv '^000$' && echo alcanzable || echo cerrado; }
EXT=$(ip -4 -o addr show scope global | awk '$2 !~ /^(docker|br-|veth|cni|flannel)/ {split($4,a,"/"); print a[1]}')
echo "puertos publicados por k3d:"; docker ps --filter name=k3d- --format '  {{.Names}} {{.Ports}}' | grep serverlb
API=$(docker port k3d-prod-serverlb 6443/tcp | head -1 | awk -F: '{print $NF}')
chk "control: interfaz por 127.0.0.1:8445" "$(prueba https://127.0.0.1:8445/)" alcanzable
chk "control: API de prod por 127.0.0.1:$API" "$(prueba https://127.0.0.1:$API/version)" alcanzable
for ip in $EXT; do
  chk "interfaz por $ip:8445" "$(prueba https://$ip:8445/)" cerrado
  chk "API de prod por $ip:$API" "$(prueba https://$ip:$API/version)" cerrado
done
echo "Resultado: $ok correctas, $fail fallidas"; exit $((fail>0))
