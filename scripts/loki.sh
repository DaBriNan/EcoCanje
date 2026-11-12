#!/bin/bash
# Uso: scripts/loki.sh <dev|prod> '<LogQL>' [desde=10m] [limite=5]  — consulta Loki (exit 0 con resultados, 2 sin resultados, 1 error)
CTX=k3d-${1:?prod}; Q=${2:?LogQL}; DESDE=${3:-10m}; LIM=${4:-5}
kubectl --context "$CTX" -n monitoring port-forward svc/loki 13100:3100 >/dev/null 2>&1 & PF=$!
trap 'kill $PF 2>/dev/null' EXIT
for i in $(seq 1 20); do curl -sf localhost:13100/ready >/dev/null && break; sleep 1; done
S=$(( ($(date +%s) - $(echo "$DESDE" | sed 's/m$/*60/;s/h$/*3600/' | bc)) * 1000000000 ))
curl -sG localhost:13100/loki/api/v1/query_range --data-urlencode "query=$Q" --data-urlencode "start=$S" --data-urlencode "limit=$LIM" --data-urlencode "direction=backward" | python3 -c '
import sys, json, datetime
d = json.load(sys.stdin)
if d.get("status") != "success": print("error:", d); sys.exit(1)
r = d["data"]["result"]
if not r: print("(sin resultados)"); sys.exit(2)
for s in r:
    m = s.get("metric", s.get("stream")) or {}
    et = ", ".join(f"{k}={v}" for k, v in sorted(m.items()) if k in ("namespace","app","container","node","pod","job","reason","kind","cluster"))
    if d["data"]["resultType"] == "matrix": print(et or "-", "->", s["values"][-1][1])
    else:
        for ts, linea in s["values"]:
            print(datetime.datetime.fromtimestamp(int(ts)/1e9).strftime("%H:%M:%S"), "|", et, "|", linea[:160])
'
