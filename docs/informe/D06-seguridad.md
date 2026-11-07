# D06. Plan y configuración de seguridad

## Controles por capa

| Capa | Control | Dónde | Evidencia |
|---|---|---|---|
| Aplicación | Contraseñas con bcrypt; autorización en servidor por rol (middleware `Rol`); validación con reglas de Laravel (tipos, rangos, unicidad, existencia); consultas por ORM/consultas parametrizadas; límite de 5 intentos de inicio de sesión por minuto y 10 registros; errores en JSON sin trazas (`APP_DEBUG=false`); la API responde 401 en JSON aunque falte `Accept` | `backend/` | E09, `tests/roles.sh`, `tests/catalogo.sh` |
| Navegador y API | TLS de la CA local (mkcert) en Traefik; mismo origen (sin CORS); token Bearer en `sessionStorage` sin cookies (CSRF no aplica); token de 8 h; CSP `default-src 'self'` sin scripts en línea, `frame-ancestors 'none'`, HSTS, `nosniff`, `no-referrer` | `frontend/seguridad.conf`, `infra/base/ingreso.yaml` | E02, captura de cabeceras |
| Contenedores | No root (uid fijo), `allowPrivilegeEscalation: false`, `capabilities: drop [ALL]`, `seccompProfile: RuntimeDefault`, sistema de archivos de solo lectura (escritura solo en `emptyDir` acotados), límites de CPU y memoria | todos los manifiestos y valores de Helm | admisión Pod Security `restricted` (rechazaría lo contrario) |
| Kubernetes | Pod Security Admission `restricted` en `ecocanje` y `monitoring`; excepción `privileged` solo en `monitoring-nodos` (node-exporter necesita el host); cuentas de servicio por carga sin token montado; RBAC por función para personas; cuota y LimitRange | `infra/base/namespace.yaml`, `cuentas.yaml`, `rbac.yaml`, `cuotas.yaml` | E09 `tests/rbac.sh` 19/19 |
| Secretos | Generados dentro de cada clúster por script (nunca en Git ni en imágenes), cifrado de Secrets en reposo (`--secrets-encryption`), montados como archivos `0440` o variables de entorno; llaves TLS, de respaldo y de usuarios fuera del repositorio (`~/.local/share/ecocanje-pki`, permisos 700/600); gancho pre-commit y `validar.sh` buscan secretos | `scripts/crear-secretos*.sh`, `crear-tls.sh`, `crear-usuario.sh` | SEC01, SEC02, CI |
| Datos | Cuentas de base de datos por función, sin rol administrativo para la aplicación (ver tabla); respaldos cifrados AES-256 fuera del clúster | `infra/base/postgres.yaml`, `mongo.yaml`, `scripts/exportar-respaldos.sh` | E09 (usuarios de BD), D09 |
| Red | Denegación inicial de entrada y salida en `ecocanje`; flujos permitidos explícitos (ver matriz); bases sin Ingress ni NodePort; API de Kubernetes y entrada publicadas solo en 127.0.0.1 | `infra/base/redes.yaml`, `frontend.yaml`, `scripts/crear-clusters.sh` | E08 (backend, frontend, exposición 6/6) |
| Suministro | Imágenes por digest (o tag + digest); charts con versión fija; imágenes propias aprobadas por id y promovidas sin reconstruir; análisis con Trivy y tratamiento de hallazgos; CI en cada cambio | `kustomization.yaml`, `infra/imagen-aprobada-*.id`, `scripts/vulnerabilidades.sh`, `.github/workflows/ci.yml` | SUP01–SUP04 |
| Infraestructura | k3s actualizado a v1.36.5 por CVE de Traefik; kubeconfig de administración con permisos 600; firewall de host documentado | `infra/K3S_VERSION`, `infra/firewall/` | E14, SUP03 |

## Matriz RBAC (personas)

| Acción en `ecocanje` | lectura | despliegue | operaciones | administrador |
|---|---|---|---|---|
| Ver Pods, logs, eventos, Deployments, HPA, Jobs, Ingress, NetworkPolicy | ✔ | ✔ | ✔ | ✔ |
| Leer Secrets | ✘ | ✘ | ✘ | ✔ |
| Cambiar imagen, escalar, reiniciar o deshacer rollouts; borrar Pods | ✘ | ✔ | ✔ | ✔ |
| Crear Jobs (migraciones, respaldos manuales) | ✘ | ✔ | ✔ | ✔ |
| `exec` y `port-forward` (diagnóstico, respaldos) | ✘ | ✘ | ✔ | ✔ |
| Modificar NetworkPolicy, RBAC, cuotas, PVC | ✘ | ✘ | ✘ | ✔ |
| Otros namespaces (`monitoring`, `kube-system`) | ✘ | ✘ | ✘ | ✔ |

Los permisos se otorgan a grupos (`ecocanje:lectura`, `ecocanje:despliegue`, `ecocanje:operaciones`); la identidad viaja
en un certificado de cliente emitido por la API `CertificateSigningRequest`, con vigencia de 30 días. Kubernetes no
revoca certificados de cliente: para retirar un acceso se quita el grupo del RoleBinding o se espera el vencimiento.
`operaciones` puede leer el entorno de un contenedor con `exec`; por eso esa función se asigna solo a quien opera
respaldos e incidentes. Las cargas usan cuentas de servicio propias (`backend`, `postgres`, `mongo`, `respaldo`,
`exportador`) sin token montado: ninguna necesita la API de Kubernetes. Las excepciones son Alloy y Prometheus, que leen
la API con roles de solo lectura de sus charts.

## Cuentas de base de datos (mínimo privilegio)

| Cuenta | PostgreSQL | MongoDB | Usa |
|---|---|---|---|
| `ecocanje_admin` / `root` | superusuario (solo inicialización y diagnóstico) | `root` | no la usa ninguna carga |
| `ecocanje_migrador` | dueño del esquema `public` | `readWrite` + `dbAdmin` en `ecocanje` | Job de migraciones |
| `ecocanje_app` | `SELECT, INSERT, UPDATE, DELETE` en tablas, uso de secuencias; sin DDL | `readWrite` en `ecocanje` | backend y worker |
| `ecocanje_backup` | `pg_read_all_data` | `backup` | CronJobs de respaldo |
| `ecocanje_monitor` | `pg_monitor` | `clusterMonitor` | exportadores |

`PUBLIC` sin privilegios sobre la base ni el esquema; autenticación `scram-sha-256` (se retiró `trust`, hallazgo de
E09 del 27 oct).

## Flujos de red permitidos

| Origen | Destino | Puerto | Política |
|---|---|---|---|
| Todos los Pods de `ecocanje` | CoreDNS (kube-system) | 53 UDP/TCP | `permitir-dns` |
| Traefik (kube-system) | backend | 8080 | `backend-ingreso` |
| Traefik (kube-system) | frontend | 8080 | `frontend-ingreso` |
| Pods con `postgres-egress` (backend, worker, migraciones, respaldo, exportador) | postgres | 5432 | `clientes-postgres-egreso` + `postgres-ingreso` |
| Pods con `mongo-egress` | mongo | 27017 | `clientes-mongo-egreso` + `mongo-ingreso` |
| Prometheus (monitoring) | exportadores | 9187, 9216 | `exportadores-desde-prometheus` |
| Pods de `monitoring` | Pods de `monitoring` | todos | `solo-ingreso-del-mismo-namespace` |
| Cualquier otro | — | — | `denegar-todo` (entrada y salida) |

Demostración A/B en E08: el mismo cliente es rechazado por la política de entrada, conecta con una regla temporal que lo
permite y vuelve a ser rechazado al retirarla; DNS y HTTPS sirven de control.

## Firewall

Docker inserta sus reglas antes que el firewall del host, de modo que un puerto publicado en `0.0.0.0` queda alcanzable
desde la LAN aunque firewalld esté activo. El control efectivo es publicar en `127.0.0.1` (`crear-clusters.sh`); antes
de corregirlo la API de Kubernetes y la entrada respondían desde la Wi-Fi y desde ZeroTier (E08, FALLA 2/6 → 6/6).
La zona de firewalld `infra/firewall/ecocanje.xml` (DROP; permite 9993/udp de ZeroTier y, como excepción documentada,
10250 y 6443 del otro clúster que comparte el host) queda **documentada y no activada** por decisión del propietario
del equipo. Orden de evaluación: puertos permitidos de la zona y después el target DROP; las respuestas a conexiones
salientes siguen permitidas. Se activa, revierte y exporta con `infra/firewall/aplicar.sh`.

## Secretos (creación, rotación y recuperación)

- **Creación:** `scripts/crear-secretos.sh <contexto>` genera contraseñas aleatorias con `openssl rand` y crea los
  Secrets solo si no existen; nunca imprime valores.
- **Rotación de una contraseña de base de datos:** generar el valor nuevo, aplicarlo en el motor con la cuenta
  administrativa (`ALTER ROLE … PASSWORD` o `db.changeUserPassword`) leyendo el valor desde un archivo, actualizar el
  Secret con `kubectl create secret … --dry-run=client -o yaml | kubectl apply -f -` y reiniciar las cargas
  (`rollout restart`). Rotación completa ejecutada en dev tras una exposición accidental (SEC02, 27 oct).
- **Rotación de todo un ambiente:** recrearlo con `bootstrap.sh` regenera todos los Secrets, el token de unión de k3s y
  la contraseña de Grafana (así se rotó el `K3S_TOKEN` expuesto en una sesión el 5 nov).
- **Recuperación:** los Secrets no se respaldan en claro; los respaldos de datos se cifran con
  `~/.local/share/ecocanje-pki/respaldo.key`, que debe guardarse fuera del equipo (D09).

## Vulnerabilidades (Trivy 0.76.1, 6 nov) y tratamiento

| Hallazgo CRITICAL | Componente | Decisión |
|---|---|---|
| CVE-2026-111497 (brotli) | frontend ≤ 0.1.0 | **Corregido**: `apk upgrade` sobre la base; frontend 0.1.1+ con 0 CRITICAL y 0 HIGH |
| CVE-2026-111497 (brotli) | sidecar nginx del backend (imagen oficial 1.30.6) | **Aceptado**: no hay compilación corregida publicada; nginx no enlaza brotli (solo `image_filter`, no cargado, y curl/freetype, no usados) |
| CVE-2025-68121 (Go en `gosu`) | postgres, mongo oficiales | **Aceptado**: corren como uid 70/999, `gosu` no se ejecuta y no usa TLS |
| CVE-2026-65600, CVE-2026-88007 | Traefik 3.6.13 | **Corregido**: k3s v1.36.5 trae Traefik 3.7.13 (0 CRITICAL) |
| CVE-2026-33186, CVE-2025-68121 | metrics-server, klipper-helm de k3s v1.36.1 | **Corregido** con k3s v1.36.5 (0 CRITICAL) |

Las imágenes propias (backend 0.1.3, frontend 0.1.4) tienen 0 CRITICAL y 0 HIGH. Los HIGH de componentes de terceros
quedan como riesgo residual y se revisan con cada actualización.

## Riesgos residuales

| Riesgo | Mitigación actual | Siguiente paso |
|---|---|---|
| Host único compartido por ambos ambientes y el otro clúster | publicación solo local; Pod Security; cuotas | hosts separados |
| Imagen base del backend `php:8.4-fpm-alpine` sin digest | imagen aprobada por id y promovida sin reconstruir; Trivy 0/0 | fijar `php:8.4.x-fpm-alpine@sha256` en la próxima versión |
| HIGH en imágenes de terceros | versiones fijadas, análisis periódico | actualizar charts y k3s en cada parche |
| Certificados de cliente no revocables | vigencia de 30 días | OIDC con revocación |
| `exec` de la función operaciones expone variables de entorno | función restringida a quien opera | credenciales solo como archivos, no como variables |
| Firewall de host no activado | publicación solo en loopback | activar `infra/firewall/aplicar.sh` si el equipo se expone |
| Sin auditoría de la API de Kubernetes | logs de eventos en Loki | activar `--audit-log-path` en k3s |
