# D09. Respaldos, restauración y continuidad

## Objetivos (definidos el 2 nov, antes de medir; `docs/rpo-rto.md`)

- **RPO 24 h**: respaldos diarios; la pérdida máxima aceptable es un día de operaciones.
- **RTO 30 min**: desde el inicio de la restauración hasta que la aplicación atiende con los datos restaurados.

## Respaldos

| Motor | Método (consistente) | Programación | Verificación al respaldar | Retención |
|---|---|---|---|---|
| PostgreSQL | `pg_dump -Fc` con la cuenta `ecocanje_backup` (`pg_read_all_data`): instantánea transaccional | CronJob `respaldo-postgres` 02:00 America/Mexico_City | `pg_restore --list` del archivo, SHA-256 escrito y comprobado; línea `respaldo_ok archivo=… bytes=… fecha=…` | 7 archivos en el PVC `respaldos` |
| MongoDB | `mongodump --archive --gzip` con la cuenta `ecocanje_backup` (rol `backup`) | CronJob `respaldo-mongo` 02:10 | tamaño mínimo (> 100 bytes) y SHA-256; `respaldo_ok`. La validez completa se comprueba al restaurar | 7 archivos |

Ambos respaldos esperan hasta 10 minutos a que su base responda (`pg_isready` y un `ping` de `mongosh`). La espera de
MongoDB se agregó el 12 nov: sin ella, cada reinicio del equipo dejaba fallar el respaldo mientras el nodo de la base
se recuperaba, y entre el 7 y el 12 nov no hubo respaldo exitoso de MongoDB en prod (alerta RespaldoFallido real, OBS05). Ambos corren como no root,
con `concurrencyPolicy: Forbid`, `activeDeadlineSeconds: 900` y `backoffLimit: 1`. No se copian archivos de datos en
caliente.

**Fuera del clúster:** `scripts/exportar-respaldos.sh <amb>` copia los respaldos a `~/ecocanje-respaldos/<amb>/`,
cifrados con AES-256 (llave en `~/.local/share/ecocanje-pki/respaldo.key`, permisos 600) y con su SHA-256. La llave
debe guardarse además fuera del equipo: sin ella los respaldos exportados no se pueden leer.

## Restauración (`scripts/restaurar.sh <amb>`)

Restaura **en el namespace aislado `recuperacion`** (`infra/recuperacion`), nunca sobre el origen: crea bases nuevas,
carga el último respaldo de cada motor, levanta la aplicación contra ellas y compara con el origen: conteos por tabla y
colección, relaciones sin huérfanos, índices, validador de MongoDB, salud de la aplicación y autorización por rol con
los usuarios restaurados.

## Resultados medidos (prod, E13)

| Medición | Resultado | Objetivo |
|---|---|---|
| Restauración de ambas bases en espacio aislado | 6/6 verificaciones (conteos, relaciones, índices, validador, aplicación, roles) | — |
| **RTO** | **60 s** (2 nov 15:59) y **27 s** (2 nov 18:32) | 1800 s: cumple |
| **RPO** (prueba con marcador) | Un dato escrito después del respaldo existe en el origen y **no** en la restauración: la pérdida real es todo lo escrito desde el último respaldo; con respaldos diarios, hasta 24 h | 24 h: cumple por diseño |
| Antigüedad del respaldo usado | 2364 s al restaurar | < 86400 s |

El primer intento de la prueba de RPO falló (3/4) porque la verificación consultó la aplicación restaurada antes de que
estuviera lista; se repitió con espera activa (4/4). Ambas corridas se conservan.

## Fallos de respaldo registrados

| Fecha | Fallo | Causa | Tratamiento |
|---|---|---|---|
| 2 nov 14:35 | respaldo de PostgreSQL y exportación con FALLA (MongoDB respaldó bien en el mismo momento) | `pg_dump` recibió *Connection refused* al iniciar el Job con la base sana; causa probable: la regla de red del Pod nuevo aún no estaba programada por kube-router (mismo efecto medido en E10). La exportación copió un `.tmp` incompleto | espera con `pg_isready` antes de `pg_dump` (absorbe el retraso); la exportación excluye `.tmp`; repetición OK |
| 3 nov | respaldos programados con `DeadlineExceeded` | el equipo estaba suspendido | alerta RespaldoFallido real (OBS05); respaldo repetido; Jobs fallidos eliminados tras el diagnóstico |
| 9, 11 y 12 nov | respaldos de MongoDB fallidos tras reiniciar el equipo (último éxito: 7 nov) | sin espera de la base; su nodo seguía caído por la IP intercambiada | espera de hasta 10 min en ambos respaldos; respaldo manual y exportación el 12 nov; alerta resuelta |

## Continuidad

| Escenario | Respuesta | Pérdida esperada |
|---|---|---|
| Caída de un Pod de aplicación | el Deployment lo recrea (6.5 s medido) | ninguna |
| Caída de la base no relacional | outbox acumula; publica al volver | ninguna (retraso del historial) |
| Caída de PostgreSQL | API en 503; recuperación automática del Pod | ninguna si el volumen sobrevive |
| Pérdida del volumen de una base | `restaurar.sh` desde el último respaldo; para MongoDB, además, republicar desde el outbox | hasta 24 h (PostgreSQL) |
| Pérdida del clúster | `bootstrap.sh` (11 min medidos) + restauración del respaldo exportado | hasta 24 h |
| Pérdida del host | nuevo host con los prerrequisitos (D05), repositorio, respaldos exportados y su llave | hasta 24 h; requiere copia externa de respaldos y llave |

Limitaciones: respaldos y clúster comparten el host y su disco; una sola réplica por motor; los respaldos exportados
deben copiarse a otro medio para cubrir la pérdida del host. Una reducción del RPO requeriría respaldos más frecuentes
o replicación continua (archivado de WAL en PostgreSQL).
