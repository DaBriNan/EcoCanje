#!/usr/bin/env python3
# Genera ecocanje.json (panel de Grafana). Uso: python3 -I generar.py > ecocanje.json
import json
B = 'service="ecocanje-backend-http@kubernetes"'
DS = {"type": "prometheus", "uid": "prometheus"}
paneles, y = [], 0

def fila(titulo):
    global y
    paneles.append({"type": "row", "title": titulo, "gridPos": {"x": 0, "y": y, "w": 24, "h": 1}, "collapsed": False}); y += 1

def p(titulo, tipo, exprs, unidad="short", w=8, h=7, x=None, umbral=None):
    global y
    if x is None: x = sum(q["gridPos"]["w"] for q in paneles if q["gridPos"]["y"] == y and q["type"] != "row")
    if x + w > 24: y += h; x = 0
    d = {"type": tipo, "title": titulo, "datasource": DS, "gridPos": {"x": x, "y": y, "w": w, "h": h},
         "targets": [{"refId": chr(65 + i), "expr": e, "legendFormat": l} for i, (e, l) in enumerate(exprs)],
         "fieldConfig": {"defaults": {"unit": unidad}, "overrides": []}, "options": {}}
    if umbral: d["fieldConfig"]["defaults"]["thresholds"] = {"mode": "absolute", "steps": umbral}
    paneles.append(d)

def salto():
    global y
    y = max(q["gridPos"]["y"] + q["gridPos"]["h"] for q in paneles)

ROJO_VERDE = [{"color": "red", "value": None}, {"color": "green", "value": 1}]
fila("Alertas y nodos")
p("Alertas activas", "table", [('ALERTS{alertstate="firing"}', "{{alertname}}")], w=8)
p("Nodos Ready", "stat", [('sum(kube_node_status_condition{condition="Ready",status="true"})', "Ready"), ('count(kube_node_info)', "Total")], w=4, umbral=ROJO_VERDE)
p("CPU por nodo", "timeseries", [('1 - avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m]))', "{{instance}}")], "percentunit", w=6)
p("Memoria disponible por nodo", "timeseries", [('node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes', "{{instance}}")], "percentunit", w=6)
salto()
p("Disco libre (/var/lib/rancher/k3s)", "timeseries", [('node_filesystem_avail_bytes{mountpoint="/var/lib/rancher/k3s"} / node_filesystem_size_bytes{mountpoint="/var/lib/rancher/k3s"}', "{{instance}}")], "percentunit")
p("Red por nodo (recibido / enviado)", "timeseries", [('sum by (instance) (rate(node_network_receive_bytes_total{device!~"lo|veth.*|flannel.*|cni.*"}[5m]))', "rx {{instance}}"), ('sum by (instance) (rate(node_network_transmit_bytes_total{device!~"lo|veth.*|flannel.*|cni.*"}[5m]))', "tx {{instance}}")], "Bps")
p("CPU asignable libre (cores)", "stat", [('sum(kube_node_status_allocatable{resource="cpu"}) - sum(kube_pod_container_resource_requests{resource="cpu"})', "libre")], "short")
salto()
fila("Kubernetes (ecocanje)")
p("Replicas deseadas vs disponibles", "timeseries", [('kube_deployment_spec_replicas{namespace="ecocanje"}', "deseadas {{deployment}}"), ('kube_deployment_status_replicas_available{namespace="ecocanje"}', "disponibles {{deployment}}")])
p("HPA del backend", "timeseries", [('kube_horizontalpodautoscaler_status_current_replicas{namespace="ecocanje"}', "actuales"), ('kube_horizontalpodautoscaler_status_desired_replicas{namespace="ecocanje"}', "deseadas"), ('kube_horizontalpodautoscaler_spec_max_replicas{namespace="ecocanje"}', "maximo")])
p("Pods no listos, Pending y reinicios (1h)", "timeseries", [('sum(kube_pod_status_ready{namespace="ecocanje",condition="false"})', "no listos"), ('sum(kube_pod_status_phase{namespace="ecocanje",phase="Pending"})', "Pending"), ('sum(increase(kube_pod_container_status_restarts_total{namespace="ecocanje"}[1h]))', "reinicios")])
salto()
p("Replicas del backend por nodo", "bargauge", [('count by (node) (kube_pod_info{namespace="ecocanje",created_by_kind="ReplicaSet",pod=~"backend-.*"})', "{{node}}")])
fila("Aplicacion (via Traefik)")
p("Trafico por codigo (req/s)", "timeseries", [(f'sum by (code) (rate(traefik_service_requests_total{{{B}}}[5m]))', "{{code}}")], "reqps")
p("Tasa de errores 5xx", "timeseries", [(f'(sum(rate(traefik_service_requests_total{{{B},code=~"5.."}}[5m])) or vector(0)) / sum(rate(traefik_service_requests_total{{{B}}}[5m]))', "5xx")], "percentunit")
p("Duracion p95 / p50", "timeseries", [(f'histogram_quantile(0.95, sum by (le) (rate(traefik_service_request_duration_seconds_bucket{{{B}}}[5m])))', "p95"), (f'histogram_quantile(0.50, sum by (le) (rate(traefik_service_request_duration_seconds_bucket{{{B}}}[5m])))', "p50")], "s")
salto()
p("Dias para expirar el certificado TLS", "stat", [('min((traefik_tls_certs_not_after - time()) / 86400)', "dias")], "d", umbral=[{"color": "red", "value": None}, {"color": "orange", "value": 7}, {"color": "green", "value": 30}])
salto()
fila("PostgreSQL")
p("PostgreSQL arriba", "stat", [('pg_up', "pg_up")], w=4, umbral=ROJO_VERDE)
p("Conexiones por estado", "timeseries", [('sum by (state) (pg_stat_activity_count{datname="ecocanje"})', "{{state}}"), ('pg_settings_max_connections', "maximo")], w=7)
p("Transacciones/s", "timeseries", [('rate(pg_stat_database_xact_commit{datname="ecocanje"}[5m])', "commit"), ('rate(pg_stat_database_xact_rollback{datname="ecocanje"}[5m])', "rollback")], w=7)
p("Tamano de la base", "stat", [('pg_database_size_bytes{datname="ecocanje"}', "ecocanje")], "bytes", w=6)
salto()
fila("MongoDB")
p("MongoDB arriba", "stat", [('mongodb_up', "mongodb_up")], w=4, umbral=ROJO_VERDE)
p("Conexiones actuales", "timeseries", [('mongodb_ss_connections{conn_type="current"}', "actuales"), ('mongodb_ss_connections{conn_type="available"}', "disponibles")], w=7)
p("Operaciones/s", "timeseries", [('sum by (legacy_op_type) (rate(mongodb_ss_opcounters[5m]))', "{{legacy_op_type}}")], "ops", w=7)
p("Latencia media por operacion", "timeseries", [('rate(mongodb_ss_opLatencies_latency[5m]) / clamp_min(rate(mongodb_ss_opLatencies_ops[5m]), 1e-9) / 1e6', "{{op_type}}")], "s", w=6)
salto()
p("Tamano de datos (ecocanje)", "stat", [('sum(mongodb_dbstats_dataSize{database="ecocanje"})', "datos")], "bytes", w=8)
salto()
fila("Respaldos")
p("Horas desde el ultimo respaldo exitoso", "stat", [('(time() - kube_cronjob_status_last_successful_time{namespace="ecocanje"}) / 3600', "{{cronjob}}")], "h", umbral=[{"color": "green", "value": None}, {"color": "red", "value": 25}])
p("Duracion del ultimo Job de respaldo", "bargauge", [('kube_job_status_completion_time{namespace="ecocanje",job_name=~"respaldo-.*"} - kube_job_status_start_time{namespace="ecocanje",job_name=~"respaldo-.*"}', "{{job_name}}")], "s")
p("Jobs de respaldo fallidos", "stat", [('sum(kube_job_status_failed{namespace="ecocanje",job_name=~"(respaldo|manual)-.*"}) or vector(0)', "fallidos")], umbral=[{"color": "green", "value": None}, {"color": "red", "value": 1}])

print(json.dumps({"uid": "ecocanje-prod", "title": "EcoCanje - produccion", "timezone": "browser", "refresh": "30s",
                  "time": {"from": "now-3h", "to": "now"}, "schemaVersion": 39, "tags": ["ecocanje"], "panels": paneles}, indent=1, ensure_ascii=False))
