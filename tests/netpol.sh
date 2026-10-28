#!/bin/bash
CTX=${1:?contexto}; K() { kubectl --context "$CTX" -n ecocanje "$@"; }; ok=0; fail=0
chk() { if [ "$2" = "$3" ]; then echo "OK    $1 -> $2"; ok=$((ok+1)); else echo "FALLA $1 -> $2 (esperado $3)"; fail=$((fail+1)); fi; }
pod() { cat <<YAML | K apply -f - >/dev/null
apiVersion: v1
kind: Pod
metadata: {name: $1, labels: {app: prueba, $2}}
spec:
  automountServiceAccountToken: false
  securityContext: {runAsNonRoot: true, runAsUser: 70, runAsGroup: 70, seccompProfile: {type: RuntimeDefault}}
  containers:
  - name: c
    image: postgres:16-alpine
    command: ["sleep", "3600"]
    securityContext: {allowPrivilegeEscalation: false, readOnlyRootFilesystem: true, capabilities: {drop: [ALL]}}
    resources: {requests: {cpu: 10m, memory: 16Mi}, limits: {cpu: 100m, memory: 64Mi}}
YAML
}
# abierto = conecta; bloqueado = nc agota el tiempo; error-exec = el pod de prueba no responde (no cuenta como bloqueo)
alcanza() {
  K exec "$1" -- true >/dev/null 2>&1 || { echo error-exec; return; }
  K exec "$1" -- nc -z -w3 "$2" "$3" >/dev/null 2>&1 && echo abierto || echo bloqueado
}

K delete pod -l app=prueba --ignore-not-found --wait=true >/dev/null
pod cliente-permitido 'postgres-egress: permitido, postgres-ingress: permitido, mongo-egress: permitido, mongo-ingress: permitido'
pod sin-ingreso       'postgres-egress: permitido, mongo-egress: permitido'
pod sin-egreso        'postgres-ingress: permitido, mongo-ingress: permitido'
pod intruso           'rol: otro'
K wait --for=condition=Ready pod -l app=prueba --timeout=180s >/dev/null

chk "pods de prueba creados (4)"         "$(K get pods -l app=prueba --no-headers | grep -c Running)" 4
chk "servicio postgres sano (readiness)" "$(K get pod postgres-0 -o jsonpath='{.status.containerStatuses[0].ready}')" true
chk "servicio mongo sano (readiness)"    "$(K get pod mongo-0 -o jsonpath='{.status.containerStatuses[0].ready}')" true
chk "DNS funciona en el pod intruso"     "$(K exec intruso -- nslookup postgres >/dev/null 2>&1 && echo resuelve || echo falla)" resuelve
chk "postgres: cliente permitido"        "$(alcanza cliente-permitido postgres 5432)" abierto
chk "postgres: bloqueado por INGRESO"    "$(alcanza sin-ingreso postgres 5432)" bloqueado
chk "postgres: bloqueado por EGRESO"     "$(alcanza sin-egreso postgres 5432)" bloqueado
chk "postgres: intruso sin etiquetas"    "$(alcanza intruso postgres 5432)" bloqueado
chk "mongo: cliente permitido"           "$(alcanza cliente-permitido mongo 27017)" abierto
chk "mongo: bloqueado por INGRESO"       "$(alcanza sin-ingreso mongo 27017)" bloqueado
chk "mongo: bloqueado por EGRESO"        "$(alcanza sin-egreso mongo 27017)" bloqueado
chk "mongo: intruso sin etiquetas"       "$(alcanza intruso mongo 27017)" bloqueado
K delete pod -l app=prueba --wait=false >/dev/null
echo "Resultado: $ok correctas, $fail fallidas"; exit $((fail>0))
