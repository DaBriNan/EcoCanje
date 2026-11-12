#!/bin/bash
# Uso: scripts/verificar-metricas.sh prod — comprueba que cada métrica usada en alertas y panel exista en Prometheus (exit 1 si falta alguna)
set -uo pipefail
CTX=k3d-${1:?prod}; D=$(dirname "$0")/../infra/observabilidad/prod
kubectl --context "$CTX" -n monitoring port-forward svc/kps-prometheus 19090:9090 >/dev/null 2>&1 & PF=$!
trap 'kill $PF 2>/dev/null' EXIT
for i in $(seq 1 20); do curl -sf localhost:19090/-/ready >/dev/null && break; sleep 1; done
curl -s localhost:19090/api/v1/label/__name__/values | python3 -I -c '
import sys, json, re
existentes = set(json.load(sys.stdin)["data"])
exprs = []
for linea in open(sys.argv[1]).read().split("expr:")[1:]:
    exprs.append(linea.split("for:")[0])
exprs += [t["expr"] for p in json.load(open(sys.argv[2]))["panels"] for t in p.get("targets", [])]
funciones = {"sum","rate","by","on","or","and","unless","time","count","avg","min","max","histogram_quantile","increase","clamp_min","vector","le","without","ignoring"}
nombres = set()
for e in exprs:
    e = re.sub(r"\{[^}]*\}", "", e); e = re.sub(r"\[[^\]]*\]", "", e); e = re.sub(r"\b(by|on|without|ignoring)\s*\([^)]*\)", "", e); e = re.sub(r"\d+(\.\d+)?e-?\d+", "", e)
    nombres |= {n for n in re.findall(r"[a-zA-Z_:][a-zA-Z0-9_:]*", e) if n not in funciones and not n.isdigit()}
falta = sorted(n for n in nombres if n not in existentes)
for n in sorted(nombres): print(("OK    " if n in existentes else "FALTA ") + n)
print(f"{len(nombres)} metricas, {len(falta)} faltan")
sys.exit(1 if falta else 0)' "$D/alertas.yaml" "$D/paneles/ecocanje.json"
