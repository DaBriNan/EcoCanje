#!/bin/bash
# Uso: scripts/provocar-alerta.sh prod <indisponible|respaldo>
# Provoca una alerta de forma controlada, espera su activación en Prometheus (firing) y en Alertmanager,
# aplica la acción correctiva y espera su resolución. Sale con 1 si algún paso no ocurre a tiempo.
set -uo pipefail
CTX=k3d-${1:?prod}; CASO=${2:?indisponible|respaldo}
K="kubectl --context $CTX"
LIMITE=${LIMITE:-420}

$K -n monitoring port-forward svc/kps-prometheus 19090:9090 >/dev/null 2>&1 & PF1=$!
$K -n monitoring port-forward svc/kps-alertmanager 19093:9093 >/dev/null 2>&1 & PF2=$!
trap 'kill $PF1 $PF2 2>/dev/null' EXIT
for i in $(seq 1 20); do curl -sf localhost:19090/-/ready >/dev/null && curl -sf localhost:19093/-/ready >/dev/null && break; sleep 1; done

t() { date '+%T'; }
# Estado de la alerta en Prometheus: firing, pending o inactiva
prom_estado() {
  curl -s localhost:19090/api/v1/alerts | python3 -c '
import sys, json
a = [x for x in json.load(sys.stdin)["data"]["alerts"] if x["labels"]["alertname"] == sys.argv[1]]
s = {x["state"] for x in a}
print("firing" if "firing" in s else "pending" if "pending" in s else "inactiva")' "$1"
}
# Alertas activas con ese nombre en Alertmanager (cuenta y detalle)
am_activas() {
  curl -s "localhost:19093/api/v2/alerts?active=true&silenced=false&inhibited=false" | python3 -c '
import sys, json
a = [x for x in json.load(sys.stdin) if x["labels"]["alertname"] == sys.argv[1]]
for x in a: print("  alertmanager:", x["labels"]["alertname"], x["labels"].get("severity"), "desde", x["startsAt"], "|", x["annotations"].get("summary"), file=sys.stderr)
print(len(a))' "$1"
}
esperar() {  # esperar <alerta> <firing|inactiva> <prom|am>
  local ini=$SECONDS e
  while [ $((SECONDS - ini)) -lt "$LIMITE" ]; do
    if [ "$3" = prom ]; then e=$(prom_estado "$1"); else [ "$(am_activas "$1" 2>/dev/null)" -gt 0 ] && e=firing || e=inactiva; fi
    [ "$e" = "$2" ] && { echo "$(t) $1 en $3: $e (tras $((SECONDS - ini)) s)"; [ "$3" = am ] && [ "$e" = firing ] && am_activas "$1" >/dev/null; return 0; }
    sleep 10
  done
  echo "$(t) ERROR: $1 no llegó a $2 en $3 en $LIMITE s (último estado: $e)"; return 1
}

case "$CASO" in
indisponible)
  A=AplicacionIndisponible
  echo "$(t) estado inicial de $A: $(prom_estado $A)"
  $K -n ecocanje get deploy,hpa backend
  echo "$(t) FALLA: escalar backend a 0 réplicas"
  $K -n ecocanje scale deploy/backend --replicas=0
  $K -n ecocanje wait --for=delete pod -l app=backend --timeout=120s
  echo "$(t) HTTPS durante la falla: $(curl -sk -o /dev/null -w '%{http_code}' https://prod.ecocanje.test:8445/api/health/ready)"
  esperar $A pending prom; esperar $A firing prom && esperar $A firing am; R1=$?
  echo "$(t) ACCIÓN: restaurar 2 réplicas (mínimo del HPA)"
  $K -n ecocanje scale deploy/backend --replicas=2
  $K -n ecocanje rollout status deploy/backend --timeout=180s
  echo "$(t) HTTPS tras la acción: $(curl -sk -o /dev/null -w '%{http_code}' https://prod.ecocanje.test:8445/api/health/ready)"
  esperar $A inactiva prom && esperar $A inactiva am; R2=$?
  ;;
respaldo)
  A=RespaldoFallido; J=manual-falla-$(date +%H%M%S)
  IMG=$($K -n ecocanje get cronjob respaldo-postgres -o jsonpath='{.spec.jobTemplate.spec.template.spec.containers[0].image}')
  echo "$(t) estado inicial de $A: $(prom_estado $A)"
  echo "$(t) FALLA: Job $J de respaldo sin credencial montada (pg_dump debe fallar por autenticación)"
  $K -n ecocanje apply -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata: {name: $J, namespace: ecocanje, labels: {app: respaldo, prueba: alerta}}
spec:
  backoffLimit: 0
  ttlSecondsAfterFinished: 3600
  template:
    metadata: {labels: {app: respaldo, prueba: alerta, postgres-egress: permitido, postgres-ingress: permitido}}
    spec:
      restartPolicy: Never
      serviceAccountName: respaldo
      automountServiceAccountToken: false
      securityContext: {runAsNonRoot: true, runAsUser: 70, runAsGroup: 70, seccompProfile: {type: RuntimeDefault}}
      containers:
      - name: pg-dump
        image: $IMG
        command: ["/bin/sh", "-ec", "pg_dump -w -h postgres -U ecocanje_backup -d ecocanje -Fc -f /tmp/x.dump"]
        securityContext: {allowPrivilegeEscalation: false, readOnlyRootFilesystem: true, capabilities: {drop: [ALL]}}
        resources: {requests: {cpu: 50m, memory: 64Mi}, limits: {cpu: 200m, memory: 128Mi}}
        volumeMounts: [{name: tmp, mountPath: /tmp}]
      volumes: [{name: tmp, emptyDir: {sizeLimit: 64Mi}}]
EOF
  $K -n ecocanje wait --for=condition=Failed job/$J --timeout=120s
  echo "$(t) log del Job fallido:"; $K -n ecocanje logs job/$J --tail=5
  esperar $A pending prom; esperar $A firing prom && esperar $A firing am; R1=$?
  echo "$(t) ACCIÓN: eliminar el Job fallido y repetir el respaldo desde el CronJob"
  $K -n ecocanje delete job $J --wait=true
  OK=manual-ok-$(date +%H%M%S)
  $K -n ecocanje create job $OK --from=cronjob/respaldo-postgres
  $K -n ecocanje wait --for=condition=Complete job/$OK --timeout=300s && $K -n ecocanje logs job/$OK --tail=1
  esperar $A inactiva prom && esperar $A inactiva am; R2=$?
  ;;
*) echo "caso desconocido: $CASO"; exit 1;;
esac
[ "$R1" -eq 0 ] && [ "$R2" -eq 0 ] && echo "$(t) $A activada y resuelta" || { echo "$(t) $A: activación=$R1 resolución=$R2"; exit 1; }
