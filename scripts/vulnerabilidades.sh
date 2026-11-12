#!/bin/bash
# Uso: scripts/vulnerabilidades.sh <dev|prod>  — análisis de vulnerabilidades (Trivy) de todas las imágenes en ejecución.
# Reporta CRITICAL y HIGH por imagen y cuántas tienen versión corregida disponible; guarda el detalle JSON en
# docs/evidencias/vulnerabilidades/<fecha>-<ambiente>/. Sale con 1 si alguna imagen PROPIA tiene CRITICAL corregible.
set -uo pipefail
ENV=${1:?dev|prod}; CTX=k3d-$ENV; RAIZ=$(cd "$(dirname "$0")/.." && pwd)
TRIVY=docker.io/aquasec/trivy:0.76.1@sha256:790fd66d1697395d8693d1acaa1ea702406a20f109b6fc7bac8db623eca6c06c
OUT=$RAIZ/docs/evidencias/vulnerabilidades/$(date +%Y%m%d-%H%M)-$ENV; mkdir -p "$OUT"
CACHE=$HOME/.cache/ecocanje-trivy; mkdir -p "$CACHE"
mapfile -t IMGS < <(kubectl --context "$CTX" get pods -A -o jsonpath='{range .items[*]}{range .spec.containers[*]}{.image}{"\n"}{end}{range .spec.initContainers[*]}{.image}{"\n"}{end}{end}' | sort -u)
echo "analizador: Trivy 0.76.1 | imágenes en $ENV: ${#IMGS[@]} | severidades: CRITICAL, HIGH"
printf '%-74s %5s %5s %9s %9s\n' IMAGEN CRIT HIGH CRIT-corr HIGH-corr
rc=0
for img in "${IMGS[@]}"; do
  f=$OUT/$(echo "$img" | tr '/:@' '___' | cut -c1-120).json
  # Las imágenes propias (ecocanje-*) solo existen en el Docker local; las de terceros se descargan del registro.
  case "$img" in ecocanje-*|docker.io/library/ecocanje-*) src=(--image-src docker); vol=(-v /var/run/docker.sock:/var/run/docker.sock);;
                 *) src=(--image-src remote); vol=();; esac
  docker run --rm "${vol[@]}" -v "$CACHE:/root/.cache" "$TRIVY" image --quiet --scanners vuln --severity CRITICAL,HIGH \
    "${src[@]}" --format json "$img" > "$f" 2>"$f.err" || { printf '%-74s %s\n' "${img:0:74}" "ERROR: $(tail -1 "$f.err" | cut -c1-80)"; continue; }
  rm -f "$f.err"
  read -r c h cc hc < <(python3 -I -c '
import json,sys
v=[x for r in (json.load(open(sys.argv[1])).get("Results") or []) for x in (r.get("Vulnerabilities") or [])]
c=[x for x in v if x["Severity"]=="CRITICAL"]; h=[x for x in v if x["Severity"]=="HIGH"]
print(len(c), len(h), sum(1 for x in c if x.get("FixedVersion")), sum(1 for x in h if x.get("FixedVersion")))' "$f")
  printf '%-74s %5s %5s %9s %9s\n' "${img:0:74}" "$c" "$h" "$cc" "$hc"
  case "$img" in ecocanje-*) [ "$cc" -gt 0 ] && rc=1;; esac
done
echo "detalle: ${OUT#$RAIZ/}"
exit $rc
