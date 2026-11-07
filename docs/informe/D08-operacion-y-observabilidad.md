# D08. Operación, observabilidad, alertas e incidentes

## Componentes (solo prod; dev usa diagnóstico básico con `kubectl` y `metrics-server`)

| Señal | Componente | Acceso |
|---|---|---|
| Métricas | Prometheus (kube-prometheus-stack 92.17.1, retención 2 días / 2 GB), kube-state-metrics, node-exporter, métricas de Traefik, `postgres-exporter` v0.20.1 y `mongodb_exporter` 0.53.0 con usuarios `monitor` | `scripts/prom.sh prod '<PromQL>'` |
| Paneles | Grafana con el panel "EcoCanje - produccion" (33 paneles, ConfigMap generado desde `infra/observabilidad/prod/paneles/generar.py`) y la fuente Loki | `kubectl -n monitoring port-forward svc/kps-grafana 3000:80`; usuario en el Secret `grafana-admin` |
| Alertas | 8 reglas `PrometheusRule` + Alertmanager **sin receptores externos** (no se envían datos a terceros) | `kubectl -n monitoring port-forward svc/kps-alertmanager 9093` |
| Logs | Loki 3.7.9 (retención 48 h) y Alloy v1.21.1: logs de `ecocanje`, `monitoring` y `kube-system` más eventos de Kubernetes | `scripts/loki.sh prod '<LogQL>'`; Grafana → Explore |
| Correlación | `X-Request-Id` generado o propagado por nginx, devuelto al cliente, en el log JSON de Laravel, en el evento del outbox, en el log del worker y en el documento de MongoDB | `scripts/loki.sh prod '{namespace="ecocanje"} \|= "<id>"'` |

## Cobertura frente al PDF (§10)

| Objeto | Indicadores en el panel o en consultas |
|---|---|
| Nodos | Ready, CPU, memoria disponible, disco de `/var/lib/rancher/k3s`, red rx/tx, CPU asignable libre |
| Kubernetes | réplicas deseadas frente a disponibles, HPA actual/deseado/máximo, Pods no listos, Pending y reinicios, réplicas por nodo, eventos en Loki |
| Aplicación | tráfico por código, tasa de 5xx, p95/p50 (Traefik), salud de dependencias (`/api/health/ready`, `/api/health/deps`), logs con fecha y `request_id` |
| PostgreSQL | `pg_up`, conexiones por estado frente a `max_connections`, transacciones/s, tamaño de la base |
| MongoDB | `mongodb_up`, conexiones actuales/disponibles, operaciones/s, latencia media, tamaño de datos |
| Red y seguridad | días para expirar el certificado TLS, códigos 4xx/5xx en Traefik, eventos y rechazos en logs |
| Respaldos | horas desde el último respaldo exitoso, duración del último Job, Jobs fallidos (más el log `respaldo_ok` con tamaño) |

## Alertas

| Alerta | Consulta | Umbral / duración | Severidad | Acción |
|---|---|---|---|---|
| AplicacionIndisponible | `kube_deployment_status_replicas_available{deployment="backend"}` | < 1 durante 1 min | critical | escenario 1 |
| NodoNoDisponible | `kube_node_status_condition{condition="Ready",status="true"}` | == 0 durante 1 min | critical | escenario 3 |
| BaseDeDatosCaida | `up{job="ecocanje/exportadores"}`, `pg_up`, `mongodb_up` | == 0 durante 1 min | critical | escenario 4 |
| TasaErroresElevada | 5xx / total en el servicio del backend (Traefik, 5 min) | > 5 % con > 0.05 req/s, 2 min | warning | escenario 2 |
| SaturacionRecursos | CPU del contenedor php / su límite, por Pod (5 min) | > 85 % durante 5 min | warning | escenario 5 |
| NodoMemoriaBaja | `MemAvailable / MemTotal` | < 10 % durante 5 min | warning | escenario 6 |
| RespaldoFallido | `kube_job_status_failed{job_name=~"(respaldo\|manual)-.*"}` | > 0 durante 1 min | critical | escenario 7 |
| RespaldoVencido | tiempo desde el último respaldo exitoso del CronJob (o desde su creación si nunca tuvo éxito) | > 25 h durante 5 min | warning | escenario 7 |

**Probadas de forma controlada (E10):** AplicacionIndisponible (backend a 0 réplicas: pending a los 40 s, firing a los
101 s, resuelta 21 s después de restaurar) y RespaldoFallido (Job sin credencial: firing a los 72 s, resuelta 20 s
después de repetir el respaldo); ambas llegaron a Alertmanager y se resolvieron. RespaldoFallido también se disparó por
un incidente real (respaldos del 3 nov con `DeadlineExceeded` mientras el equipo estaba suspendido, OBS05).
**Umbral efectivo:** con scrape de 30 s y `for: 1m`, una caída avisa a partir de ~96 s; en E11 una caída de PostgreSQL
de 72 s dejó las alertas en pending y se resolvieron sin notificar (intencional, evita ruido).

## Operación diaria

| Tarea | Comando |
|---|---|
| Estado general | `kubectl --context k3d-prod get nodes`; `source scripts/ev.sh; pods_sanos k3d-prod` |
| Objetivos caídos y alertas activas | `scripts/prom.sh prod 'up == 0'`; `scripts/prom.sh prod 'ALERTS{alertstate="firing"}'` |
| Datos y outbox | `scripts/estado-datos.sh k3d-prod` |
| Errores recientes del backend | `scripts/loki.sh prod '{app="backend", container="php"} \| json \| level_name="ERROR"' 1h 20` |
| Seguir una solicitud | `scripts/loki.sh prod '{namespace="ecocanje"} \|= "<X-Request-Id>"' 1h 50` |
| Métricas que usan alertas y panel existen | `scripts/verificar-metricas.sh prod` |

## Manual de incidentes

Cada escenario: **diagnóstico → acciones → verificación → escalamiento**. Registrar línea de tiempo con `ev`.

**1. Aplicación indisponible** (AplicacionIndisponible; la interfaz o `/api` responden 503)
- Diagnóstico: `kubectl -n ecocanje get deploy,pods -l app=backend`; `kubectl -n ecocanje describe pod <pod>` (eventos);
  `curl …/api/health/ready` (503 `postgres_no_disponible` → escenario 4); logs `{app="backend"}` en Loki.
- Acciones: si las réplicas son 0, `kubectl -n ecocanje scale deploy/backend --replicas=2`; si CrashLoop, revisar el log
  de `php` y hacer rollback (D07); si Pending, revisar cuota y nodos (escenarios 3 y 5).
- Verificación: `/api/health/ready` = 200; alerta resuelta; `tests/roles.sh`.
- Escalamiento: si persiste tras el rollback, administrador (revisión de nodos y almacenamiento).

**2. Tasa de errores elevada** (TasaErroresElevada)
- Diagnóstico: códigos en el panel; `scripts/loki.sh prod '{app="backend", container="php"} | json | level_name="ERROR"'`;
  tomar un `request_id` y seguirlo; revisar dependencias con `/api/health/deps` (rol operador).
- Acciones: si coincide con una versión nueva, rollback (D07); si es una dependencia, escenario 4.
- Verificación: tasa de 5xx < 1 % en 10 min.
- Escalamiento: desarrollador con los `request_id` afectados.

**3. Nodo no disponible** (NodoNoDisponible)
- Diagnóstico: `kubectl get nodes`; `docker ps --filter name=k3d-prod`; `docker logs k3d-prod-agent-N | grep -i shutdown`.
- Acciones: si el log muestra `failed to find interface with specified node ip` (tras reiniciar el host, Docker
  intercambió las IP), `docker restart k3d-prod-agent-0 k3d-prod-agent-1`; si el contenedor no existe, recrear el
  ambiente (D05). Considerar que Prometheus puede estar en el nodo caído: si no hay métricas, diagnosticar con kubectl.
- Verificación: nodos Ready; `pods_sanos`; `up == 0` sin resultados.
- Escalamiento: administrador del host. Caso real: 5 nov (E11), recuperado con el reinicio de los agentes.

**4. Base de datos caída** (BaseDeDatosCaida)
- Diagnóstico: `kubectl -n ecocanje get sts,pods -l 'app in (postgres,mongo)'`; eventos; ¿el nodo de su volumen está
  Ready o acordonado? (`local-path` ata la base a su nodo).
- Acciones: PostgreSQL: la API queda en 503 sin reiniciarse (liveness no depende de la base); recuperar el Pod
  (`kubectl -n ecocanje rollout status sts/postgres`; si el nodo está acordonado, `uncordon`). MongoDB: la API sigue
  aceptando escrituras y el outbox acumula; al volver la base se publica solo.
- Verificación: `pg_up` / `mongodb_up` = 1; `scripts/estado-datos.sh` con outbox pendientes 0; documento en MongoDB por
  `request_id`.
- Escalamiento: si el volumen se perdió, restauración desde respaldo (D09). Medido (E11): MongoDB 28 s caído → publicado
  7 s después, sin duplicados; PostgreSQL 60 s caído → servicio de vuelta a los 72–75 s, 0 reinicios de backend y worker.

**5. Saturación de recursos** (SaturacionRecursos)
- Diagnóstico: `kubectl -n ecocanje get hpa backend`; `kubectl top pods`; panel de CPU y throttling; ¿el HPA está en 6?
- Acciones: si el HPA no alcanza el máximo, revisar `kubectl describe hpa` (métricas ausentes); si está en 6, el límite
  es la CPU de los Pods o del host (D03): limitar la carga o ampliar capacidad. No desplegar migraciones con el HPA en 6
  (excederían la cuota).
- Verificación: CPU por debajo del 85 % del límite; p95 < 1 s.
- Escalamiento: planeación de capacidad.

**6. Memoria baja en un nodo** (NodoMemoriaBaja)
- Diagnóstico: `kubectl top pods -A --sort-by=memory`. En k3d todos los nodos ven la memoria del host completo.
- Acciones: liberar memoria en el host (otras aplicaciones, `docker system df`) o reducir límites.
- Verificación: memoria disponible > 10 %.

**7. Respaldo fallido o vencido** (RespaldoFallido, RespaldoVencido): ver D09.

**8. Equipo suspendido o reiniciado**
- Síntomas: pruebas con huecos de horas; HPA con `FailedGetScale: Unauthorized` por unos minutos; Grafana sin pasar su
  sonda mientras se pone al día; respaldos con `DeadlineExceeded`.
- Acciones: verificar nodos (escenario 3), `pods_sanos`, `up == 0`; repetir respaldos si fallaron.
- Prevención: las evidencias y la carga corren bajo `systemd-inhibit`.

**9. Mantenimiento de un worker (drain/uncordon)**
- Procedimiento: `scripts/fallos.sh prod drain` (NODO=…): drain respetando PDB, uncordon y `rollout restart` de backend y
  frontend para reequilibrar. Medido (E11): 0 solicitudes fallidas; backend y frontend mantienen 2 réplicas en el otro
  worker; la base cuyo volumen está en ese nodo queda detenida hasta el uncordon.
