# EcoCanje

Centro de acopio y reciclaje con canje de puntos, desplegado en dos ambientes Kubernetes independientes
(desarrollo y producción). Práctica individual de Infraestructura de Servicios (ITM).

- **Aplicación**: SPA en React (frontend) y API en Laravel 12 / PHP 8.4 (backend).
- **Datos**: PostgreSQL es la fuente de verdad (usuarios, entregas, puntos, canjes); MongoDB guarda el libro de
  movimientos y las fichas de material, sincronizado desde PostgreSQL con un *outbox* idempotente.
- **Plataforma**: k3d con k3s v1.36.5 (versión en `infra/K3S_VERSION`). `k3d-dev`: 1 nodo. `k3d-prod`: 1 servidor y 2 workers, HPA 2–6 réplicas.
- **Operación**: métricas (Prometheus, Grafana, Alertmanager, exportadores de ambas bases), logs (Loki y Alloy)
  con correlación por `X-Request-Id`, respaldos programados y restauración verificada.

El expediente técnico (D01–D10) está en [`docs/informe/`](docs/informe/); la bitácora de pruebas y sus
salidas, en [`docs/evidencias/INDEX.md`](docs/evidencias/INDEX.md).

## Estructura

| Carpeta | Contenido |
|---|---|
| `frontend/` | SPA React 19 + Vite, servida por nginx sin privilegios ([Dockerfile](frontend/Dockerfile)) |
| `backend/` | API Laravel, migraciones, semillas, worker del outbox ([Dockerfile.prod](backend/Dockerfile.prod)) |
| `infra/base/` | Manifiestos comunes: namespace, cuotas, RBAC, bases, aplicación, frontend, respaldos, Ingress, NetworkPolicy |
| `infra/dev/`, `infra/prod/` | Overlays de Kustomize por ambiente (réplicas, HPA, PDB, distribución entre nodos, host) |
| `infra/observabilidad/` | Valores de Helm fijados (métricas, Loki, Alloy) y, en `prod/`, exportadores, alertas y panel |
| `infra/recuperacion/` | Espacio aislado para restaurar respaldos sin tocar el origen |
| `infra/firewall/` | Zona de firewalld del host (documentada) y script para activarla, revertirla o exportarla |
| `scripts/` | Automatización: creación, despliegue, respaldo, restauración, pruebas, validación, reconstrucción |
| `tests/` | Pruebas funcionales, de red, de interfaz (Playwright), de carga (k6) y de correlación |
| `docs/` | Informe, evidencias, manual de comandos ejecutados y objetivos de recuperación |

## Prerrequisitos del host

`docker`, `k3d`, `kubectl`, `helm`, `skopeo`, `mkcert` (con su CA instalada: `mkcert -install`), `python3` con
PyYAML, `openssl` y `bc`. En `/etc/hosts`:

```
127.0.0.1 dev.ecocanje.test prod.ecocanje.test
```

Las versiones exactas de cada componente están en [`infra/K3S_VERSION`](infra/K3S_VERSION),
[`infra/observabilidad/VERSIONES`](infra/observabilidad/VERSIONES) y en los manifiestos (imágenes fijadas por digest).

## Inicio rápido

```bash
scripts/validar.sh          # validación estática (scripts, PHP, manifiestos, Helm, secretos); no toca clústeres
scripts/bootstrap.sh        # crea dev y prod desde cero, despliega todo y verifica (~11-13 min)
```

`bootstrap.sh` se detiene si los clústeres ya existen: nunca borra nada. Los secretos no están en Git; se generan
dentro de cada clúster (`crear-secretos.sh`, `crear-secretos-monitoreo.sh`) y los certificados TLS los emite la CA
local de mkcert.

| Ambiente | Interfaz | API |
|---|---|---|
| dev | https://dev.ecocanje.test:8444/ | https://dev.ecocanje.test:8444/api |
| prod | https://prod.ecocanje.test:8445/ | https://prod.ecocanje.test:8445/api |

Ambos solo escuchan en `127.0.0.1`. Usuarios semilla: `operador@ecocanje.test` y `ciudadano1..N@ecocanje.test`; su
contraseña se lee del clúster y no se muestra:
`kubectl --context k3d-dev -n ecocanje get secret app-migracion -o jsonpath='{.data.seed-pass}' | base64 -d`.

## Operación habitual

| Tarea | Comando |
|---|---|
| Desplegar o actualizar un ambiente | `scripts/desplegar.sh <dev\|prod>` |
| Promover una versión con rollback probado | `scripts/actualizacion.sh prod <nueva> <anterior>` |
| Verificar que la imagen es la aprobada | `scripts/verificar-imagen.sh <dev\|prod> <etiqueta>` |
| Respaldar, exportar y restaurar | `scripts/respaldar.sh`, `scripts/exportar-respaldos.sh`, `scripts/restaurar.sh` |
| Consultar métricas y logs | `scripts/prom.sh prod '<PromQL>'`, `scripts/loki.sh prod '<LogQL>'` |
| Estado de los datos | `scripts/estado-datos.sh k3d-prod` |
| Recuperar tras reiniciar el equipo | `scripts/recuperar-tras-reinicio.sh` |

## Pruebas y evidencias

Cada prueba importante se ejecuta con `ev` (de [`scripts/ev.sh`](scripts/ev.sh)), que guarda la salida con fecha,
ambiente, commit y resultado en `docs/evidencias/`, oculta valores sensibles y termina con código distinto de 0 si el
estado es malo. Las corridas fallidas se conservan con su diagnóstico.

```bash
source scripts/ev.sh
ev E03 "Flujo de negocio en prod" "todas OK" scripts/probar.sh prod tests/flujo.sh
```

| Prueba | Script |
|---|---|
| Roles, flujo, catálogo (API) | `tests/roles.sh`, `tests/flujo.sh`, `tests/catalogo.sh` vía `scripts/probar.sh` |
| Interfaz con navegador (completa en dev, humo de solo lectura en prod) | `scripts/probar.sh <amb> tests/interfaz/correr.sh` |
| Políticas de red y exposición | `tests/netpol-app.sh`, `tests/netpol-frontend.sh`, `tests/exposicion.sh` |
| Balanceo, carga y HPA | `tests/balanceo.sh`, `scripts/carga.sh prod <con-hpa\|sin-hpa>` |
| Fallos | `scripts/fallos.sh prod <pod\|drain\|mongo\|postgres>` |
| Alertas provocadas | `scripts/provocar-alerta.sh prod <indisponible\|respaldo>` |
| Respaldos, RPO e independencia | `scripts/restaurar.sh`, `tests/rpo.sh`, `tests/independencia.sh` |
| Correlación de logs | `scripts/probar.sh prod tests/correlacion.sh` |

**Datos de prueba solo en dev.** Las pruebas que crean datos de negocio (`flujo.sh`, `catalogo.sh`, `correlacion.sh`,
`rpo.sh`, `fallos.sh … mongo` y la prueba de interfaz completa) se niegan a correr en prod salvo que se pida con
`PERMITIR_DATOS_EN_PROD=1`; en prod, `tests/interfaz/correr.sh` ejecuta una prueba de humo de solo lectura.

La CI ([`.github/workflows/ci.yml`](.github/workflows/ci.yml)) ejecuta `scripts/validar.sh --imagenes` en cada
cambio a `main` y `dev`.
