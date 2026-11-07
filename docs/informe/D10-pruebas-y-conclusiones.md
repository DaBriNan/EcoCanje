# D10. Plan de pruebas, resultados, evidencias y conclusiones

## Método

Cada prueba se ejecuta con `ev` (`scripts/ev.sh`): guarda en `docs/evidencias/` el identificador, fecha, ambiente,
host, commit, comando, resultado esperado, salida (con valores sensibles ocultos) y resultado, y añade una fila a
[`INDEX.md`](../evidencias/INDEX.md). Las pruebas terminan con código distinto de 0 si el estado es malo. **Las corridas
fallidas se conservan** con su diagnóstico y la repetición se registra aparte; las mediciones afectadas por causas
externas se marcan como invalidadas, sin borrarlas.

Al 6 nov: **230 evidencias** (192 OK, 35 fallidas con diagnóstico, 3 invalidadas); de ellas, 129 de la matriz E01–E14.

| Tipo | Herramienta | Ubicación |
|---|---|---|
| Funcionales por API (válidos, inválidos, duplicados, sin permiso, transiciones) | bash + curl | `tests/roles.sh`, `flujo.sh`, `catalogo.sh` |
| Interfaz con navegador real (escritorio y celular) | Playwright 1.64.1 en Docker | `tests/interfaz/` (23 verificaciones) |
| Red y exposición | kubectl, nc, curl | `tests/netpol*.sh`, `exposicion.sh` |
| RBAC | certificados de cliente | `tests/rbac.sh` |
| Carga y escalado | k6 2.2.0 en Docker, series de Prometheus | `tests/carga/`, `scripts/carga.sh` |
| Fallos | kubectl, sonda HTTPS a 5 Hz | `scripts/fallos.sh`, `tests/recreacion-datos.sh` |
| Actualización y rollback | sonda, versión, prueba de roles | `scripts/actualizacion.sh`, `promover-frontend.sh` |
| Observabilidad | PromQL, LogQL, Alertmanager | `scripts/prom.sh`, `loki.sh`, `provocar-alerta.sh`, `tests/correlacion.sh` |
| Respaldos y recuperación | pg_dump, mongodump, namespace aislado | `scripts/respaldar.sh`, `restaurar.sh`, `tests/rpo.sh` |
| Estáticas y suministro | shellcheck, php -l, kubeconform, helm, Trivy, CI | `scripts/validar.sh`, `vulnerabilidades.sh`, `.github/workflows/ci.yml` |

## Matriz de aceptación

| ID | Condición (PDF §12) | Resultado | Estado |
|---|---|---|---|
| E01 | Dos contextos y topologías distintas; nodos y componentes sanos | dev 1 nodo, prod 1+2; nodos Ready y Pods sanos tras cada reconstrucción; incidente real de workers tras reiniciar el host (diagnosticado y resuelto) | Cumple |
| E02 | URLs HTTPS distintas y datos independientes | `dev.ecocanje.test:8444` y `prod.ecocanje.test:8445` con TLS; `tests/independencia.sh` sin datos, credenciales ni volúmenes compartidos | Cumple |
| E03 | CRUD de tres entidades, roles y validaciones desde interfaz y API | API: flujo 22/22, catálogo 16/16 (incluye regresión del empate de tarifas); interfaz 23/23 en dev y prod (validación en cliente y servidor, búsqueda, sesión expirada), estable en 3 corridas | Cumple |
| E04 | Uso funcional y persistente de ambas bases con consultas trazables | historial y fichas en MongoDB; outbox sin duplicados; correlación de una solicitud hasta el documento (OBS07) | Cumple |
| E05 | Recreación de Pods de datos sin pérdida | huella de 6 métricas en PostgreSQL y 2 en MongoDB idéntica tras recrear ambos Pods (8 s c/u, mismo PVC) en dev y prod; la primera corrida dio un falso OK y se invalidó | Cumple |
| E06 | HPA crece y disminuye; series y carga adjuntas | 2 → 6 → 2 (333 s); p95 0.99 s, 0 % errores, 124 rps; sin HPA p95 12.6 s, 13 % errores; CSV en `evidencias/carga/`. Una corrida invalidada por suspensión del equipo; la 0.1.1 no cumplía (cuello en PostgreSQL) | Cumple (p95 con poco margen) |
| E07 | Varias réplicas atienden; distribuidas entre workers | 60 solicitudes: 30/30 entre dos réplicas en workers distintos (logs de nginx) | Cumple |
| E08 | Conexiones permitidas y denegadas; DNS y servicios como control | A/B con regla temporal para backend y frontend; el frontend no alcanza bases ni backend; exposición solo en 127.0.0.1 (6/6 tras corregir 0.0.0.0) | Cumple |
| E09 | Acceso denegado por rol de aplicación, RBAC y usuario de base | roles de la API (incluye 401 sin `Accept`); RBAC 19/19 con certificados reales; usuarios de BD de mínimo privilegio | Cumple |
| E10 | Paneles con nodos, servicios y ambos motores; dos alertas activadas y resueltas | panel de 33 paneles con datos; AplicacionIndisponible y RespaldoFallido activadas y resueltas en Prometheus y Alertmanager; RespaldoFallido real (OBS05) | Cumple |
| E11 | Fallo de Pod y mantenimiento de worker con tiempos e impacto | Pod: 6.5 s, 0 errores; drain/uncordon: 0 errores, 2 réplicas mantenidas tras corregir el reparto; MongoDB caído: sin pérdida; PostgreSQL caído: 72–75 s, 0 reinicios | Cumple |
| E12 | Actualización y rollback con versión y funcionalidad | backend 0.1.1→0.1.2→0.1.1→0.1.2 y 0.1.2→0.1.3→0.1.2→0.1.3 con 0 errores; frontend hasta 0.1.4 con compuertas | Cumple |
| E13 | Respaldo y restauración de ambas bases; RPO y RTO | restauración aislada 6/6; RTO 60 s y 27 s; pérdida demostrada de un dato posterior al respaldo (RPO <= 24 h) | Cumple |
| E14 | Reconstrucción desde recursos limpios con el manual | 759 s, 671 s y 638 s (k3s v1.36.5); verificadas, sin pasos manuales adicionales | Cumple |

## Hallazgos que las pruebas encontraron y se corrigieron

| Hallazgo | Detectado por | Corrección |
|---|---|---|
| PostgreSQL saturado por una conexión `scram` por solicitud (p95 6.2 s) | E06 | conexiones persistentes (backend 0.1.2) |
| 3 solicitudes perdidas por rollout | sonda de E12 | `preStop` de 5 s |
| Worker del outbox en CrashLoopBackOff si cae PostgreSQL | eventos en Loki tras E11 | reintento con espera creciente (0.1.3) |
| API respondía 500 sin token ni `Accept` | correlación por `request_id` | `redirectGuestsTo` y JSON en `api/*` (0.1.3) |
| Tarifas del mismo segundo: ganaba la anterior (también en el cálculo de puntos) | prueba de interfaz | desempate por id (0.1.3) |
| Consulta N+1 en el catálogo | revisión del controlador | `DISTINCT ON` (0.1.3) |
| Réplicas en Pending durante el drain y 4 réplicas en un solo worker tras un rollout | E11 | `nodeTaintsPolicy: Honor`, `matchLabelKeys` |
| API de Kubernetes y entrada alcanzables desde la LAN y la VPN | revisión de puertos publicados | publicación en 127.0.0.1 |
| CVE crítico en la base del frontend y en Traefik | Trivy | `apk upgrade` (frontend 0.1.1); k3s v1.36.5 |
| Validación solo en servidor; sin búsqueda; respuestas viejas pisaban a las nuevas; un 401 tardío cerraba una sesión nueva | revisión de requisitos y prueba de interfaz | frontend 0.1.2–0.1.4 |
| Exportador de PostgreSQL sin permiso para leer su credencial | OBS04 | `fsGroup` |

## Conclusiones

- Los dos ambientes cumplen la matriz E01–E14 con evidencia reproducible, y prod puede reconstruirse desde cero en unos
  11 minutos con un solo script.
- Las pruebas encontraron once defectos reales que una revisión estática no habría mostrado; cada uno tiene su
  evidencia, su corrección y, cuando aplica, una prueba de regresión.
- El HPA solo mejora el servicio cuando el cuello de botella está en el backend: con 0.1.1 subir de 2 a 6 réplicas no
  cambió el rendimiento porque PostgreSQL estaba saturado.
- La alta disponibilidad es parcial: la aplicación sobrevive a la pérdida de un Pod y al mantenimiento de un worker sin
  errores, pero cada base es un punto único de fallo y su volumen queda atado a un nodo.

## Limitaciones

- Un solo host físico para ambos ambientes (y para otro clúster ajeno): sin tolerancia a la falla del host; los nodos
  de k3d comparten CPU y memoria aunque cada uno declare el total.
- Control plane único, una réplica por motor, almacenamiento `local-path` sin replicación.
- El p95 de 0.99 s cumple por poco: el siguiente límite es la CPU del backend y del host.
- Monitoreo dentro del mismo clúster que monitorea.
- Firewall de host documentado pero no activado; sin auditoría de la API de Kubernetes.
- Imagen base del backend sin digest; HIGH residuales en imágenes de terceros.
- Dos suspensiones del equipo afectaron pruebas largas (una invalidada, otra con un hueco de 4 h entre fases).

## Referencias

- Kubernetes: https://kubernetes.io/docs/ (Workloads, Services, Ingress, NetworkPolicy, Pod Security Standards, RBAC,
  HPA, PodDisruptionBudget, CertificateSigningRequest)
- k3s: https://docs.k3s.io/ — k3d: https://k3d.io/
- Traefik: https://doc.traefik.io/traefik/
- Laravel 12: https://laravel.com/docs/12.x — Sanctum
- PostgreSQL: https://www.postgresql.org/docs/ — MongoDB: https://www.mongodb.com/docs/manual/
- kube-prometheus-stack: https://github.com/prometheus-community/helm-charts — Prometheus Operator CRD
- Grafana Loki: https://grafana.com/docs/loki/ — Grafana Alloy: https://grafana.com/docs/alloy/
- k6: https://grafana.com/docs/k6/ — Playwright: https://playwright.dev/
- Trivy: https://trivy.dev/ — kubeconform: https://github.com/yannh/kubeconform
- Patrón outbox: https://microservices.io/patterns/data/transactional-outbox.html
- Práctica individual Kubernetes: desarrollo y producción (documento del curso, no incluido en el repositorio)
