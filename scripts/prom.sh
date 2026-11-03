#!/bin/bash
# Uso: scripts/prom.sh <dev|prod> '<consulta PromQL>'   (exit 0 con resultados, 2 sin resultados, 1 error)
CTX=k3d-${1:?dev|prod}; Q=${2:?consulta}
kubectl --context "$CTX" -n monitoring port-forward svc/kps-prometheus 19090:9090 >/dev/null 2>&1 & PF=$!
trap 'kill $PF 2>/dev/null' EXIT
for i in $(seq 1 20); do curl -sf localhost:19090/-/ready >/dev/null && break; sleep 1; done
curl -sG localhost:19090/api/v1/query --data-urlencode "query=$Q" | python3 -c '
import sys, json
d = json.load(sys.stdin)
if d.get("status") != "success": print("error:", d); sys.exit(1)
r = d["data"]["result"]
if not r: print("(sin resultados)"); sys.exit(2)
for x in r:
    m = x["metric"]; v = x["value"][1]
    print(", ".join(f"{k}={m[k]}" for k in sorted(m) if k in ("job","instance","namespace","pod","service","alertname","code","deployment","node","condition")) or "-", "->", v)
'
