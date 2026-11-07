#!/bin/bash
# Uso: scripts/crear-usuario.sh <dev|prod> <usuario> <lectura|despliegue|operaciones> [dias=30]
# Emite un certificado de cliente para una persona con la API CertificateSigningRequest del clúster
# (firmante kubernetes.io/kube-apiserver-client). Grupo = ecocanje:<función> (campo O), que infra/base/rbac.yaml vincula.
# La llave privada se genera en el host y no sale de ~/.local/share/ecocanje-pki/usuarios (permisos 600).
# Revocación: los certificados de cliente no se revocan en Kubernetes; se retira el permiso quitando el grupo del
# RoleBinding o esperando el vencimiento (por eso la vigencia es corta).
set -euo pipefail
ENV=${1:?dev|prod}; U=${2:?usuario}; F=${3:?lectura|despliegue|operaciones}; DIAS=${4:-30}; CTX=k3d-$ENV
case "$F" in lectura|despliegue|operaciones) ;; *) echo "función inválida: $F"; exit 1;; esac
[[ "$U" =~ ^[a-z][a-z0-9.-]{1,30}$ ]] || { echo "usuario inválido"; exit 1; }
D=$HOME/.local/share/ecocanje-pki/usuarios; mkdir -p "$D"; chmod 700 "$D"
B=$D/$ENV-$U; CSR=ecocanje-$ENV-$U
( umask 077; openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out "$B.key" 2>/dev/null )
openssl req -new -key "$B.key" -subj "/CN=$U/O=ecocanje:$F" -out "$B.csr"
kubectl --context "$CTX" delete csr "$CSR" --ignore-not-found >/dev/null
cat <<EOF | kubectl --context "$CTX" apply -f - >/dev/null
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata: {name: $CSR}
spec:
  request: $(base64 -w0 < "$B.csr")
  signerName: kubernetes.io/kube-apiserver-client
  expirationSeconds: $((DIAS * 86400))
  usages: [client auth]
EOF
kubectl --context "$CTX" certificate approve "$CSR" >/dev/null
for i in $(seq 1 20); do C=$(kubectl --context "$CTX" get csr "$CSR" -o jsonpath='{.status.certificate}'); [ -n "$C" ] && break; sleep 1; done
[ -n "$C" ] || { echo "el clúster no emitió el certificado"; exit 1; }
echo "$C" | base64 -d > "$B.crt"; rm -f "$B.csr"
SERVER=$(kubectl config view --raw -o jsonpath="{.clusters[?(@.name=='$CTX')].cluster.server}")
kubectl config view --raw -o jsonpath="{.clusters[?(@.name=='$CTX')].cluster.certificate-authority-data}" | base64 -d > "$B.ca"
KC=$B.kubeconfig; rm -f "$KC"; ( umask 077; touch "$KC" )
kubectl --kubeconfig "$KC" config set-cluster "$CTX" --server="$SERVER" --certificate-authority="$B.ca" --embed-certs >/dev/null
kubectl --kubeconfig "$KC" config set-credentials "$U" --client-certificate="$B.crt" --client-key="$B.key" --embed-certs >/dev/null
kubectl --kubeconfig "$KC" config set-context "$U@$CTX" --cluster="$CTX" --user="$U" --namespace=ecocanje >/dev/null
kubectl --kubeconfig "$KC" config use-context "$U@$CTX" >/dev/null
chmod 600 "$B".*; rm -f "$B.ca"
echo "usuario $U (grupo ecocanje:$F) en $ENV; vence: $(openssl x509 -in "$B.crt" -noout -enddate | cut -d= -f2)"
echo "kubeconfig: $KC"
