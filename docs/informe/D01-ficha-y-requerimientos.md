# D01. Ficha del proyecto y requerimientos

## Ficha

| Campo | Valor |
|---|---|
| Proyecto | EcoCanje: centro de acopio y reciclaje con canje de puntos |
| Materia | Infraestructura de Servicios — práctica individual de Kubernetes (ITM) |
| Repositorio | https://github.com/DaBriNan/EcoCanje (rama `dev`; versión entregada etiquetada `v1.0.0`) |
| Problema | Un centro de acopio necesita registrar el material que entregan los ciudadanos, pesarlo y validarlo, acreditar puntos según una tarifa vigente por material y permitir canjear esos puntos por recompensas, con trazabilidad de cada movimiento. |
| Usuarios | **Ciudadano**: consulta tarifas, su saldo, sus entregas e historial; solicita canjes. **Operador**: registra y procesa entregas, administra el catálogo (materiales, tarifas, fichas, recompensas), aprueba y entrega canjes, consulta el reporte mensual. |
| Alcance técnico | SPA React, API Laravel, PostgreSQL (fuente de verdad) y MongoDB (libro de movimientos y fichas) en dos clústeres k3s independientes (dev y prod) sobre k3d, con observabilidad, respaldos, seguridad y automatización. |

## Reglas de negocio principales

| Regla | Implementación |
|---|---|
| Una entrega pasa por `registrada → pesada → validada → acreditada`; puede rechazarse con motivo desde los tres primeros estados. Cualquier otra transición devuelve 409. | `EntregaController::paso()` con bloqueo de fila (`lockForUpdate`) |
| Los puntos se calculan con la tarifa vigente **al registrar** cada detalle (peso × puntos/kg, redondeado). La tarifa vigente es la más reciente con `vigente_desde ≤ ahora`; empate en el mismo segundo: la de mayor id. | `EntregaController::store`, `acreditar` |
| Tope diario de 500 puntos acreditados por ciudadano; los puntos vencen a los 12 meses. | `PuntosService::TOPE_DIARIO`, `VIGENCIA_MESES` |
| Un canje consume puntos de los lotes más antiguos primero (FIFO); cancelarlo devuelve los puntos a sus lotes y el stock. | `PuntosService::consumir`, `CanjeController::cancelar` |
| Un canje pasa por `solicitado → aprobado → entregado`; puede cancelarse desde los dos primeros. | `CanjeController::paso()` |
| Materiales y recompensas se dan de baja lógicamente (`activo`/`activa = false`) para conservar el historial de entregas y canjes. | `MaterialController::destroy`, `RecompensaController::destroy` |
| Cada cambio de estado de negocio registra un evento en el *outbox* en la misma transacción; el worker lo publica en MongoDB de forma idempotente. | `PuntosService::evento`, `PublicarOutbox` |

## Requerimientos funcionales

| ID | Requerimiento (PDF §2) | Criterio de aceptación | Verificación |
|---|---|---|---|
| RF01 | Interfaz navegable y adaptable con formularios, errores y confirmaciones | Ambas vistas operan en escritorio y en celular (390 px); cada operación muestra confirmación o error | `tests/interfaz/e03.mjs` (capturas), E03 |
| RF02 | Backend con API y reglas de dominio; el navegador no accede a las bases | Las bases no tienen Service expuesto ni ruta de Ingress; el frontend no alcanza las bases (NetworkPolicy) | `tests/netpol-frontend.sh`, E08 |
| RF03 | CRUD de tres entidades relacionadas | Materiales (con tarifas y ficha), recompensas y entregas (con detalles): alta, consulta, modificación y baja lógica | `tests/catalogo.sh`, `tests/flujo.sh`, E03 |
| RF04 | Autenticación y dos roles con autorización en servidor | Ciudadano recibe 403 en rutas de operador; sin token 401 aunque falte `Accept: application/json` | `tests/roles.sh`, E09 |
| RF05 | Validación de tipos, obligatorios, rangos, unicidad y relaciones, en cliente y servidor | El navegador bloquea datos fuera de rango; la API devuelve 422 por campo aunque se evite la interfaz | `tests/catalogo.sh`, `e03.mjs`, E03 |
| RF06 | Búsqueda, paginación y un reporte útil | Entregas filtrables por estado y ciudadano, paginadas de 15 en 15; historial paginado; reporte mensual por material | `tests/catalogo.sh`, `e03.mjs` |
| RF07 | Flujo propio con estados y transiciones válidas | Entregas y canjes con las transiciones de la tabla anterior; transiciones inválidas → 409 | `tests/flujo.sh` (22 verificaciones) |
| RF08 | Semilla reproducible de al menos 100 registros sin datos reales | `db:seed` crea operador, ciudadanos ficticios, catálogo y más de 100 entregas | Job `migraciones`, `scripts/estado-datos.sh` |
| RF09 | Uso real de la base no relacional | Historial de movimientos y fichas técnicas de material se leen y escriben en MongoDB con validación de esquema e índices | `tests/catalogo.sh`, `tests/correlacion.sh` |
| RF10 | Fuente de verdad y recuperación entre motores sin duplicados | PostgreSQL es la fuente de verdad; con MongoDB caído las escrituras siguen y el outbox reconcilia sin duplicados | `scripts/fallos.sh prod mongo`, E04, E11 |

## Requerimientos no funcionales

| ID | Requerimiento | Criterio de aceptación | Resultado medido |
|---|---|---|---|
| RNF01 | Dos ambientes independientes | Clústeres, contextos, credenciales, datos y volúmenes separados; prod con 1 control plane y 2 workers | `tests/independencia.sh`, E01, E02 |
| RNF02 | Publicación HTTPS con nombres distintos | `dev.ecocanje.test:8444` y `prod.ecocanje.test:8445` con TLS de la CA local | E02 |
| RNF03 | Rendimiento bajo carga | p95 < 1 s y errores < 1 % con 50 usuarios virtuales en prod | **p95 0.99 s, 0 % errores, 124 rps** (E06, con HPA); sin HPA: p95 12.6 s, 13 % |
| RNF04 | Escalado horizontal | HPA 2–6 crece por encima de 2 con carga y regresa al mínimo | 2 → 6 → 2 en 333 s (E06) |
| RNF05 | Disponibilidad ante fallos voluntarios | Borrado de Pod y drain de worker sin solicitudes fallidas | 0 errores en ambos casos (E11) |
| RNF06 | Actualización sin corte y rollback | Rolling update, rollback y nueva promoción sin errores en la sonda | 0 errores en las tres fases (E12) |
| RNF07 | Observabilidad | Métricas de nodos, Kubernetes, aplicación y ambas bases; logs centralizados con correlación; 8 alertas, 2 provocadas | E10, OBS04–OBS07 |
| RNF08 | Recuperación | RPO objetivo 24 h y RTO objetivo 30 min, medidos | ver D09 |
| RNF09 | Seguridad | Pod Security restricted, NetworkPolicy de denegación inicial, RBAC por función, secretos fuera de Git, imágenes por digest, análisis de vulnerabilidades | E08, E09, SUP03, D06 |
| RNF10 | Reconstrucción reproducible | Dev y prod desde cero con un solo script, sin pasos tácitos | 759 s, 671 s y una tercera corrida con k3s v1.36.5 (E14, ver D05) |
