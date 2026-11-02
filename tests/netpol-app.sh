#!/bin/bash
# Uso: tests/netpol-app.sh <dev|prod>  — el backend solo acepta trafico de Traefik (A/B con y sin la politica)
ENV=${1:?dev|prod}; CTX=k3d-$ENV; PORT=$([ "$ENV" = dev ] && echo 8444 || echo 8445)
K() { kubectl --context "$CTX" -n ecocanje "$@"; }; ok=0; fail=0
chk() { if [ "$2" = "$3" ]; then echo "OK    $1 -> $2"; ok=$((ok+1)); else echo "FALLA $1 -> $2 (esperado $3)"; fail=$((fail+1)); fi; }
alcanza() { K exec "$1" -- true >/dev/null 2>&1 || { echo error-exec; return; }
            K exec "$1" -- nc -z -w3 "$2" "$3" >/dev/null 2>&1 && echo abierto || echo bloqueado; }
limpiar() { K delete pod cliente-ext --ignore-not-found --wait=false >/dev/null; K delete networkpolicy prueba-egreso-backend --ignore-not-found >/dev/null
            K apply -f infra/base/redes.yaml >/dev/null; }
trap limpiar EXIT

K delete pod cliente-ext --ignore-not-found --wait=true >/dev/null
cat <<'YAML' | K apply -f - >/dev/null
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: prueba-egreso-backend}
spec:
  podSelector: {matchLabels: {prueba: egreso-backend}}
  policyTypes: [Egress]
  egress:
  - to: [{podSelector: {matchLabels: {app: backend}}}]
    ports: [{protocol: TCP, port: 8080}]
---
apiVersion: v1
kind: Pod
metadata: {name: cliente-ext, labels: {app: prueba, prueba: egreso-backend}}
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
K wait --for=condition=Ready pod/cliente-ext --timeout=180s >/dev/null
IP=$(K get pod -l app=backend -o jsonpath='{.items[0].status.podIP}'); sleep 4

chk "backend sano (todas las replicas Ready)" "$(K get pods -l app=backend -o jsonpath='{range .items[*]}{.status.containerStatuses[*].ready}{" "}{end}' | tr ' ' '\n' | grep -vc true)" 0
chk "DNS resuelve el backend desde el cliente" "$(K exec cliente-ext -- nslookup backend.ecocanje.svc.cluster.local >/dev/null 2>&1 && echo resuelve || echo falla)" resuelve
chk "con politica: cliente con egreso permitido bloqueado por INGRESO del backend" "$(alcanza cliente-ext $IP 8080)" bloqueado
K delete networkpolicy backend-ingreso >/dev/null; sleep 5
chk "sin la politica de ingreso: el mismo cliente conecta (el servicio estaba sano)" "$(alcanza cliente-ext $IP 8080)" abierto
K apply -f infra/base/redes.yaml >/dev/null; sleep 5
chk "politica restaurada: bloqueado de nuevo" "$(alcanza cliente-ext $IP 8080)" bloqueado
chk "la entrada HTTPS (Traefik) sigue pasando" "$(curl -s -o /dev/null -w '%{http_code}' https://$ENV.ecocanje.test:$PORT/api/health/ready)" 200
echo "Resultado: $ok correctas, $fail fallidas"; exit $((fail>0))
