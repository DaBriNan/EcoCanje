#!/bin/bash
# Uso: tests/netpol-frontend.sh <dev|prod>  — E08 del frontend: sin salida a bases ni backend; solo Traefik entra (A/B con regla temporal)
ENV=${1:?dev|prod}; CTX=k3d-$ENV; PORT=$([ "$ENV" = dev ] && echo 8444 || echo 8445)
K() { kubectl --context "$CTX" -n ecocanje "$@"; }; ok=0; fail=0
chk() { if [ "$2" = "$3" ]; then echo "OK    $1 -> $2"; ok=$((ok+1)); else echo "FALLA $1 -> $2 (esperado $3)"; fail=$((fail+1)); fi; }
alcanza() { K exec "$1" -- nc -z -w3 "$2" "$3" >/dev/null 2>&1 && echo abierto || echo bloqueado; }
limpiar() { K delete networkpolicy prueba-egreso-frontend prueba-ingreso-frontend --ignore-not-found >/dev/null
            K delete pod cliente-fe --ignore-not-found --wait=true >/dev/null; }
trap limpiar EXIT; limpiar
FE=$(K get pod -l app=frontend -o jsonpath='{.items[0].metadata.name}')

echo "== Salida desde el frontend ($FE)"
chk "DNS resuelve postgres (control: DNS permitido)" "$(K exec "$FE" -- nslookup postgres.ecocanje.svc.cluster.local >/dev/null 2>&1 && echo resuelve || echo falla)" resuelve
chk "frontend -> PostgreSQL 5432" "$(alcanza "$FE" postgres 5432)" bloqueado
chk "frontend -> MongoDB 27017" "$(alcanza "$FE" mongo 27017)" bloqueado
chk "frontend -> backend 80 (el navegador usa el Ingress, no el pod)" "$(alcanza "$FE" backend 80)" bloqueado

echo "== Entrada al frontend"
cat <<'YAML' | sed "s#image: postgres:16-alpine#image: $(K get cronjob respaldo-postgres -o jsonpath='{.spec.jobTemplate.spec.template.spec.containers[0].image}')#" | K apply -f - >/dev/null
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: prueba-egreso-frontend}
spec:
  podSelector: {matchLabels: {prueba: egreso-frontend}}
  policyTypes: [Egress]
  egress:
  - to: [{podSelector: {matchLabels: {app: frontend}}}]
    ports: [{protocol: TCP, port: 8080}]
---
apiVersion: v1
kind: Pod
metadata: {name: cliente-fe, labels: {app: prueba, prueba: egreso-frontend}}
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
K wait --for=condition=Ready pod/cliente-fe --timeout=180s >/dev/null
IP=$(K get pod "$FE" -o jsonpath='{.status.podIP}'); sleep 4
chk "cliente con salida permitida, bloqueado por la ENTRADA del frontend" "$(alcanza cliente-fe "$IP" 8080)" bloqueado
cat <<'YAML' | sed "s#image: postgres:16-alpine#image: $(K get cronjob respaldo-postgres -o jsonpath='{.spec.jobTemplate.spec.template.spec.containers[0].image}')#" | K apply -f - >/dev/null
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: prueba-ingreso-frontend}
spec:
  podSelector: {matchLabels: {app: frontend}}
  policyTypes: [Ingress]
  ingress:
  - from: [{podSelector: {matchLabels: {prueba: egreso-frontend}}}]
    ports: [{protocol: TCP, port: 8080}]
YAML
sleep 5
chk "con regla temporal: el mismo cliente conecta (el frontend estaba sano)" "$(alcanza cliente-fe "$IP" 8080)" abierto
K delete networkpolicy prueba-ingreso-frontend >/dev/null; sleep 5
chk "regla temporal retirada: bloqueado de nuevo" "$(alcanza cliente-fe "$IP" 8080)" bloqueado
chk "la entrada HTTPS por Traefik sigue sirviendo la interfaz" "$(curl -s -o /dev/null -w '%{http_code}' https://$ENV.ecocanje.test:$PORT/)" 200
echo "Resultado: $ok correctas, $fail fallidas"; exit $((fail>0))
