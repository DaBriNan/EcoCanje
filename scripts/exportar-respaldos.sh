#!/bin/bash
# Uso: scripts/exportar-respaldos.sh <dev|prod>  — copia los respaldos fuera del cluster, cifrados (AES-256) y con SHA-256
set -euo pipefail
ENV=${1:?dev|prod}; CTX=k3d-$ENV; DEST=$HOME/ecocanje-respaldos/$ENV; KEY=$HOME/.local/share/ecocanje-pki/respaldo.key
K() { kubectl --context "$CTX" -n ecocanje "$@"; }
mkdir -p "$DEST" "$(dirname "$KEY")"; chmod 700 "$HOME/ecocanje-respaldos" "$DEST"
[ -f "$KEY" ] || ( umask 077; openssl rand -base64 48 > "$KEY" ); chmod 600 "$KEY"
K delete pod lector-respaldos --ignore-not-found --wait=true >/dev/null
cat <<'YAML' | sed "s#image: postgres:16-alpine#image: $(K get cronjob respaldo-postgres -o jsonpath='{.spec.jobTemplate.spec.template.spec.containers[0].image}')#" | K apply -f - >/dev/null
apiVersion: v1
kind: Pod
metadata: {name: lector-respaldos, labels: {app: lector}}
spec:
  automountServiceAccountToken: false
  securityContext: {runAsNonRoot: true, runAsUser: 70, runAsGroup: 70, seccompProfile: {type: RuntimeDefault}}
  containers:
  - name: c
    image: postgres:16-alpine
    command: ["sleep", "600"]
    securityContext: {allowPrivilegeEscalation: false, readOnlyRootFilesystem: true, capabilities: {drop: [ALL]}}
    resources: {requests: {cpu: 10m, memory: 16Mi}, limits: {cpu: 100m, memory: 64Mi}}
    volumeMounts: [{name: r, mountPath: /respaldos, readOnly: true}]
  volumes: [{name: r, persistentVolumeClaim: {claimName: respaldos, readOnly: true}}]
YAML
K wait --for=condition=Ready pod/lector-respaldos --timeout=180s >/dev/null
TMP=$(mktemp -d); trap 'rm -rf "$TMP"; K delete pod lector-respaldos --ignore-not-found --wait=false >/dev/null' EXIT
K exec lector-respaldos -- tar cf - -C /respaldos . | tar xf - -C "$TMP"
n=0
while read -r f; do
  b=$(basename "$f"); [ -f "$DEST/$b.enc" ] && continue
  (cd "$(dirname "$f")" && sha256sum -c "$b.sha256" >/dev/null) || { echo "FALLA integridad de $b"; exit 1; }
  openssl enc -aes-256-cbc -pbkdf2 -salt -in "$f" -out "$DEST/$b.enc" -pass file:"$KEY"
  (cd "$DEST" && sha256sum "$b.enc" > "$b.enc.sha256")
  echo "exportado y cifrado: $b.enc ($(stat -c %s "$DEST/$b.enc") bytes)"; n=$((n+1))
done < <(find "$TMP" -type f ! -name "*.sha256" ! -name "*.tmp")
echo "nuevos respaldos exportados: $n"; ls -l "$DEST" | grep -v '\.sha256'
