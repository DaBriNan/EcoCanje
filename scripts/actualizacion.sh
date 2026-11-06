#!/bin/bash
# Uso: scripts/actualizacion.sh prod <nueva> <anterior>   — E12: actualización gradual, rollback y nueva promoción.
# Requiere que infra/prod/kustomization.yaml ya declare <nueva> y que <nueva> esté aprobada (infra/imagen-aprobada-<nueva>.id).
# Una sonda HTTPS cada 0.2 s mide el efecto de cada fase. Sale con 1 si alguna verificación falla.
set -uo pipefail
ENV=${1:?prod}; NUEVA=${2:?nueva}; ANT=${3:?anterior}; CTX=k3d-$ENV
K="kubectl --context $CTX -n ecocanje"; URL=https://$ENV.ecocanje.test:8445/api
SONDA=$(mktemp); rc=0; t() { date '+%T'; }
trap 'kill ${SPID:-} 2>/dev/null; rm -f "$SONDA"' EXIT

sonda_ini() { : > "$SONDA"; ( while :; do echo "$(date +%s.%N | cut -c1-14) $(curl -s -o /dev/null -m 2 -w '%{http_code}' $URL/health/ready)"; sleep 0.2; done ) >> "$SONDA" & SPID=$!; }
sonda_fin() { kill $SPID 2>/dev/null; wait $SPID 2>/dev/null
  awk '{n++; if ($2!="200") {f++; c[$2]++}} END {printf "  sonda %s: %d solicitudes, %d sin 200 (%.2f%%)", fase, n, f, 100*f/n; for (k in c) printf " [código %s: %d]", k, c[k]; print ""; exit (f>0)}' fase="$1" "$SONDA" || { [ "${2:-}" = tolerar ] || rc=1; }; }
version() { curl -s $URL/health/live | python3 -c 'import sys,json; print(json.load(sys.stdin).get("version","sin campo version"))'; }
imagenes() { $K get pods -l 'app in (backend,outbox-worker)' --field-selector=status.phase=Running -o jsonpath='{range .items[*]}{.metadata.deletionTimestamp}|{.metadata.labels.app}={.spec.containers[0].image} {end}' | tr ' ' '\n' | grep '^|' | cut -c2- | tr '\n' ' '; }
esperar_rollout() { $K rollout status deploy/backend --timeout=300s >/dev/null && $K rollout status deploy/outbox-worker --timeout=300s >/dev/null; }
verificar() {  # verificar <versión esperada>
  local v; v=$(version); echo "$(t) versión en /health/live: $v | pods: $(imagenes)"
  if [ "$1" = "$ANT" ]; then [ "$v" = "sin campo version" ] || { echo "  esperado $ANT (sin campo version)"; rc=1; }
  else [ "$v" = "$1" ] || { echo "  esperado $1"; rc=1; }; fi
  imagenes | tr ' ' '\n' | grep -v "^$" | grep -vq ":$1$" && { echo "  hay pods con otra imagen"; rc=1; }
  local o r; o=$(scripts/probar.sh "$ENV" tests/roles.sh 2>&1); r=$?
  echo "$(t) prueba funcional (roles): $(echo "$o" | tail -1)"; [ $r -eq 0 ] || { echo "$o"; rc=1; }
}

echo "$(t) 0. Imagen $NUEVA en $ENV"
k3d image import ecocanje-backend:$NUEVA -c "$ENV" 2>&1 | tail -1
scripts/verificar-imagen.sh "$ENV" "$NUEVA" || { echo "ERROR: la imagen no es la aprobada"; exit 1; }
grep -q "newTag: \"$NUEVA\"" infra/$ENV/kustomization.yaml || { echo "ERROR: infra/$ENV no declara $NUEVA"; exit 1; }

echo "$(t) 1. Estado inicial"; verificar "$ANT"; sleep 61

echo "$(t) 2. ACTUALIZACIÓN a $NUEVA (migraciones y rolling update)"; sonda_ini; T=$(date +%s)
scripts/desplegar.sh "$ENV" >/dev/null || rc=1
esperar_rollout; echo "$(t) actualización completa en $(( $(date +%s) - T )) s"; sleep 3; sonda_fin actualizacion
$K rollout history deploy/backend | tail -3
verificar "$NUEVA"; sleep 61

echo "$(t) 3. ROLLBACK a $ANT (kubectl rollout undo)"; sonda_ini; T=$(date +%s)
$K rollout undo deploy/backend && $K rollout undo deploy/outbox-worker
esperar_rollout; echo "$(t) rollback completo en $(( $(date +%s) - T )) s"; sleep 3; sonda_fin rollback
verificar "$ANT"; sleep 61

echo "$(t) 4. NUEVA PROMOCIÓN de $NUEVA desde el estado declarado en git (kubectl apply -k infra/$ENV)"; sonda_ini; T=$(date +%s)
kubectl --context $CTX apply -k infra/$ENV >/dev/null; esperar_rollout
echo "$(t) promoción completa en $(( $(date +%s) - T )) s"; sleep 3; sonda_fin promocion
verificar "$NUEVA"
exit $rc
