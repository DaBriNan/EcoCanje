#!/bin/bash
# Uso: scripts/carga.sh prod <con-hpa|sin-hpa|humo>
# Experimento E06: verifica la API de métricas, línea base de 5 min, carga k6 progresiva, espera el
# regreso del HPA y exporta series de Prometheus a docs/evidencias/carga/<fecha>-<etiqueta>/.
# Código de salida: 0 si se cumple el umbral (p95<1s, errores<1%) y, con HPA, si crece por encima de 2
# réplicas y regresa a 2; 1 en otro caso.
set -uo pipefail
ENV=${1:?prod}; ETQ=${2:?con-hpa|sin-hpa|humo}; CTX=k3d-$ENV
K="kubectl --context $CTX -n ecocanje"
RAIZ=$(cd "$(dirname "$0")/.." && pwd)
K6_IMG="grafana/k6:2.2.0@sha256:9bd01d6941fca969cb61bb57d2da5ee9b385fe2aa8881df3798c196564d6ace6"
BASE=${BASE_SEG:-300}; ENFRIAR_MAX=${ENFRIAR_MAX:-600}
[ "$ETQ" = humo ] && BASE=0 ENFRIAR_MAX=0
OUT=$RAIZ/docs/evidencias/carga/$(date +%Y%m%d-%H%M)-$ETQ; mkdir -p "$OUT"
t() { date '+%T'; }

echo "$(t) 1. API de métricas (requisito antes de probar)"
$K top pods -l app=backend || { echo "ERROR: metrics API no disponible"; exit 1; }
$K get hpa backend -o jsonpath='{"HPA min="}{.spec.minReplicas}{" max="}{.spec.maxReplicas}{" objetivo="}{.spec.metrics[0].resource.target.averageUtilization}{"% actual="}{.status.currentMetrics[0].resource.current.averageUtilization}{"%\n"}'
echo "requests por pod (base del % del HPA): $($K get deploy backend -o jsonpath='{range .spec.template.spec.containers[*]}{.name}={.resources.requests.cpu} {end}')"

# Muestreo cada 15 s: réplicas (HPA y Deployment) y nodo de cada réplica
( echo "hora,hpa_deseadas,hpa_actuales,deploy_ready,cpu_hpa_pct,pods_por_nodo"
  while :; do
    H=$($K get hpa backend -o jsonpath='{.status.desiredReplicas},{.status.currentReplicas},{.status.currentMetrics[0].resource.current.averageUtilization}')
    R=$($K get deploy backend -o jsonpath='{.status.readyReplicas}')
    N=$($K get pods -l app=backend -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' | sort | uniq -c | awk '{printf "%s:%s ", $2, $1}')
    IFS=, read -r d c u <<< "$H"; echo "$(t),$d,$c,${R:-0},$u,$N"; sleep 15
  done ) > "$OUT/replicas.csv" & MUESTREO=$!
trap 'kill $MUESTREO 2>/dev/null' EXIT

if [ "$BASE" -gt 0 ]; then
  MIN=$($K get hpa backend -o jsonpath='{.spec.minReplicas}'); W=$SECONDS
  echo "$(t) 1b. Esperar a que el backend esté en minReplicas=$MIN antes de la línea base (máx 900 s)"
  until [ "$($K get hpa backend -o jsonpath='{.status.currentReplicas}')" = "$MIN" ] && [ "$($K get deploy backend -o jsonpath='{.status.readyReplicas}')" = "$MIN" ]; do
    [ $((SECONDS - W)) -gt 900 ] && { echo "ERROR: no regresó a $MIN réplicas"; exit 1; }; sleep 15
  done; echo "$(t) en $MIN réplicas tras $((SECONDS - W)) s"
fi
T0=$(date +%s)
if [ "$BASE" -gt 0 ]; then echo "$(t) 2. Línea base sin carga: $BASE s"; sleep "$BASE"; fi
T1=$(date +%s)

echo "$(t) 3. Carga con k6 ($K6_IMG), generador limitado a 1.5 CPU en el host $(hostname)"
SEED_PW=$($K get secret app-migracion -o jsonpath='{.data.seed-pass}' | base64 -d)
CA=$(mkcert -CAROOT)/rootCA.pem
GEN=k6-e06-$ETQ-$$
( echo "hora,cpu,mem"; while sleep 15; do docker stats --no-stream --format '{{.CPUPerc}},{{.MemUsage}}' "$GEN" 2>/dev/null | sed "s/^/$(t),/" || break; done ) > "$OUT/generador.csv" &
GENST=$!
docker run --rm --name "$GEN" --network host --cpus 1.5 --user "$(id -u):$(id -g)" \
  -v "$RAIZ/tests/carga:/scripts:ro" -v "$CA:/ca.pem:ro" -v "$OUT:/out" \
  -e SSL_CERT_FILE=/ca.pem -e BASE="https://$ENV.ecocanje.test:8445/api" -e USUARIO=ciudadano1@ecocanje.test \
  -e SEED_PW="$SEED_PW" -e PERFIL="$([ "$ETQ" = humo ] && echo humo || echo rampa)" \
  "$K6_IMG" run --quiet --summary-export /out/k6-resumen.json /scripts/escenario.js 2>&1 | tail -40
K6RC=${PIPESTATUS[0]}; unset SEED_PW
kill $GENST 2>/dev/null
T2=$(date +%s)

if [ "$ENFRIAR_MAX" -gt 0 ]; then
  echo "$(t) 4. Sin carga: esperar regreso a minReplicas (máx $ENFRIAR_MAX s; estabilización declarada 120 s)"
  MIN=$($K get hpa backend -o jsonpath='{.spec.minReplicas}')
  while [ $(( $(date +%s) - T2 )) -lt "$ENFRIAR_MAX" ]; do
    [ "$($K get hpa backend -o jsonpath='{.status.currentReplicas}')" = "$MIN" ] && [ $(( $(date +%s) - T2 )) -gt 150 ] && break
    sleep 15
  done
  echo "$(t) réplicas tras $(( $(date +%s) - T2 )) s sin carga: $($K get hpa backend -o jsonpath='{.status.currentReplicas}')"
fi
T3=$(date +%s); sleep 20; kill $MUESTREO 2>/dev/null

echo "$(t) 5. Exportar series de Prometheus ($T0 a $T3)"
$K -n monitoring port-forward svc/kps-prometheus 19090:9090 >/dev/null 2>&1 & PF=$!
trap 'kill $MUESTREO $PF 2>/dev/null' EXIT
for i in $(seq 1 20); do curl -sf localhost:19090/-/ready >/dev/null && break; sleep 1; done
B='service="ecocanje-backend-http@kubernetes"'
python3 -I - "$OUT" "$T0" "$T1" "$T2" "$T3" "$B" <<'EOF'
import sys, json, csv, urllib.request, urllib.parse
out, t0, t1, t2, t3, b = sys.argv[1], *map(int, sys.argv[2:6]), sys.argv[6]
Q = {
 "hpa_deseadas": 'kube_horizontalpodautoscaler_status_desired_replicas{namespace="ecocanje"}',
 "hpa_actuales": 'kube_horizontalpodautoscaler_status_current_replicas{namespace="ecocanje"}',
 "deploy_ready": 'kube_deployment_status_replicas_ready{namespace="ecocanje",deployment="backend"}',
 "cpu_backend_cores": 'sum(rate(container_cpu_usage_seconds_total{namespace="ecocanje",pod=~"backend-.*",container!=""}[1m]))',
 "mem_backend_bytes": 'sum(container_memory_working_set_bytes{namespace="ecocanje",pod=~"backend-.*",container!=""})',
 "rps": f'sum(rate(traefik_service_requests_total{{{b}}}[1m]))',
 "errores_ratio": f'(sum(rate(traefik_service_requests_total{{{b},code=~"5.."}}[1m])) or vector(0)) / sum(rate(traefik_service_requests_total{{{b}}}[1m]))',
 "p95_s": f'histogram_quantile(0.95, sum by (le) (rate(traefik_service_request_duration_seconds_bucket{{{b}}}[1m])))',
 "pg_conexiones": 'sum(pg_stat_activity_count{datname="ecocanje"})',
 "mongo_conexiones": 'sum(mongodb_ss_connections{conn_type="current"})',
 "cpu_nodos_pct": '100 * (1 - avg(rate(node_cpu_seconds_total{mode="idle"}[1m])))',
}
series = {}
for k, q in Q.items():
    u = "http://localhost:19090/api/v1/query_range?" + urllib.parse.urlencode({"query": q, "start": t0, "end": t3, "step": 15})
    r = json.load(urllib.request.urlopen(u))["data"]["result"]
    series[k] = {int(float(ts)): float(v) for ts, v in (r[0]["values"] if r else [])}
ts = sorted({x for s in series.values() for x in s})
with open(f"{out}/series-prometheus.csv", "w", newline="") as f:
    w = csv.writer(f); w.writerow(["epoch", "fase"] + list(Q))
    for x in ts:
        fase = "base" if x < t1 else "carga" if x < t2 else "enfriamiento"
        w.writerow([x, fase] + [("%.4g" % series[k][x]) if x in series[k] else "" for k in Q])
def resumen(fase, a, z):
    def agg(k, fn):
        v = [series[k][x] for x in ts if a <= x < z and x in series[k] and series[k][x] == series[k][x]]  # sin NaN
        return ("%.3g" % fn(v)) if v else "-"
    print(f"  {fase:13s} réplicas max={agg('hpa_actuales', max)}  rps prom={agg('rps', lambda v: sum(v)/len(v))}  "
          f"p95 max={agg('p95_s', max)} s  errores max={agg('errores_ratio', max)}  cpu backend max={agg('cpu_backend_cores', max)} cores  "
          f"pg max={agg('pg_conexiones', max)}  mongo max={agg('mongo_conexiones', max)}")
print("Resumen por fase (Prometheus, paso 15 s):")
if t1 > t0: resumen("base", t0, t1)
resumen("carga", t1, t2)
if t3 > t2: resumen("enfriamiento", t2, t3 + 1)
json.dump({"t0_inicio_base": t0, "t1_inicio_carga": t1, "t2_fin_carga": t2, "t3_fin": t3}, open(f"{out}/ventanas.json", "w"))
EOF

echo "$(t) 6. Resultado"
python3 -I - "$OUT/k6-resumen.json" <<'EOF'
import sys, json
m = json.load(open(sys.argv[1]))["metrics"]
d, f, r = m["http_req_duration{scenario:consulta}"], m["http_req_failed{scenario:consulta}"], m["http_reqs"]
print(f"k6 (solo escenario, sin login de setup): solicitudes totales={r['count']} ({r['rate']:.1f}/s)  p95={d['p(95)']:.0f} ms  p99={d['p(99)']:.0f} ms  max={d['max']:.0f} ms  errores={100*f['value']:.2f}%")
print("umbral p95<1000 ms:", "CUMPLE" if d['p(95)'] < 1000 else "NO CUMPLE", "| umbral errores<1%:", "CUMPLE" if f['value'] < 0.01 else "NO CUMPLE")
EOF
MAXR=$(awk -F, 'NR>1 && $3>m {m=$3} END{print m+0}' "$OUT/replicas.csv")
FINR=$(awk -F, 'NR>1 {f=$3} END{print f}' "$OUT/replicas.csv")
echo "réplicas: máximo observado=$MAXR, final=$FINR (muestreo kubectl en replicas.csv)"
echo "archivos: ${OUT#$RAIZ/}"
RC=0; [ "$K6RC" -eq 0 ] || { echo "k6 terminó con $K6RC (umbral no cumplido o error)"; RC=1; }
if [ "$ETQ" = con-hpa ]; then
  [ "$MAXR" -gt 2 ] || { echo "el HPA no creció por encima de 2"; RC=1; }
  [ "$FINR" = 2 ] || { echo "no regresó a 2 réplicas en $ENFRIAR_MAX s"; RC=1; }
fi
exit $RC
