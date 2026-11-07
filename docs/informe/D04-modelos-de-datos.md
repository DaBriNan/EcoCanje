# D04. Modelos y diccionarios de datos, migraciones y consistencia

## PostgreSQL (fuente de verdad)

```mermaid
erDiagram
  users ||--o{ entregas : "entrega (user_id)"
  users ||--o{ entregas : "procesa (operador_id)"
  users ||--o{ canjes : solicita
  users ||--o{ puntos_lotes : posee
  users ||--o{ personal_access_tokens : autentica
  materiales ||--o{ tarifas : "tiene historial"
  materiales ||--o{ entrega_detalles : "se entrega"
  tarifas ||--o{ entrega_detalles : "valoriza"
  entregas ||--|{ entrega_detalles : contiene
  entregas ||--o| puntos_lotes : genera
  recompensas ||--o{ canjes : "se canjea"
  users { bigint id PK; string email UK; string rol; string password "hash bcrypt" }
  materiales { bigint id PK; string nombre UK; bool activo }
  tarifas { bigint id PK; bigint material_id FK; int puntos_por_kg; timestamp vigente_desde }
  entregas { bigint id PK; bigint user_id FK; bigint operador_id FK; string estado; string motivo_rechazo }
  entrega_detalles { bigint id PK; bigint entrega_id FK; bigint material_id FK; bigint tarifa_id FK; decimal peso_kg; int puntos }
  recompensas { bigint id PK; string nombre; string tipo; int costo_puntos; int stock; bool activa }
  canjes { bigint id PK; bigint user_id FK; bigint recompensa_id FK; int puntos; string estado; json lotes }
  puntos_lotes { bigint id PK; bigint user_id FK; bigint entrega_id FK; int puntos; int restantes; timestamp vence_en }
  outbox { uuid id PK; string tipo; json payload; timestamp publicado_en; smallint intentos }
```

### Diccionario

| Tabla | Columna | Tipo | Restricción / índice | Significado |
|---|---|---|---|---|
| users | rol | varchar(20) | default `ciudadano` | `ciudadano` u `operador`; define la autorización en la API |
| materiales | nombre | varchar(80) | UNIQUE | Material reciclable; `activo=false` es baja lógica |
| tarifas | material_id, vigente_desde | FK, timestamp | índice (material_id, vigente_desde) | Historial de precios; vigente = la más reciente ≤ ahora (desempate por id) |
| entregas | estado | varchar(20) | índice (user_id, estado) | `registrada, pesada, validada, acreditada, rechazada` |
| entrega_detalles | tarifa_id | FK a tarifas | | Tarifa congelada al registrar: un cambio posterior no altera la entrega |
| entrega_detalles | peso_kg | decimal(8,2) | validación 0.1–200 en la API | Peso registrado y después pesado |
| recompensas | tipo | varchar(20) | validación `tarjeta_regalo` o `vale_despensa` | Tipo de recompensa; `activa=false` es baja lógica |
| canjes | lotes | json | | Lotes y cantidades consumidos (FIFO) para devolverlos al cancelar |
| puntos_lotes | restantes, vence_en | int, timestamp | índice (user_id, vence_en) | Saldo = suma de `restantes` no vencidos; vigencia 12 meses |
| outbox | publicado_en | timestamp nullable | índice | `NULL` = pendiente de publicar en MongoDB; `intentos` cuenta fallos |

Llaves foráneas en todas las relaciones; las operaciones de varios pasos (registrar entrega con detalles, acreditar,
canjear, cancelar) corren en una transacción con bloqueo de fila (`SELECT … FOR UPDATE`) sobre la entrega, el canje,
la recompensa o el usuario, para serializar acreditaciones y consumos concurrentes.

### Migraciones

Laravel, en `backend/database/migrations/`, aplicadas por el Job `migraciones` en cada despliegue con la cuenta
`ecocanje_migrador` (dueña del esquema). La aplicación usa `ecocanje_app` (solo DML). Todas las migraciones tienen
`down()`; un rollback de imagen **no** revierte el esquema, por lo que cada cambio de esquema debe ser compatible con
la versión anterior (aditivo). Las versiones 0.1.1 → 0.1.3 no cambiaron el esquema (D07).

### Consultas representativas

```sql
-- Tarifa vigente de cada material en una sola consulta (antes una por material, N+1)
SELECT DISTINCT ON (material_id) material_id, puntos_por_kg
FROM tarifas WHERE vigente_desde <= now()
ORDER BY material_id, vigente_desde DESC, id DESC;

-- Saldo disponible de un ciudadano
SELECT coalesce(sum(restantes), 0) FROM puntos_lotes WHERE user_id = $1 AND vence_en > now();

-- Reporte mensual: kilos y puntos acreditados por material
SELECT m.nombre, sum(d.peso_kg) AS kilos, sum(d.puntos) AS puntos
FROM entrega_detalles d JOIN entregas e ON e.id = d.entrega_id JOIN materiales m ON m.id = d.material_id
WHERE e.estado = 'acreditada' AND e.created_at >= $1 AND e.created_at < $2
GROUP BY m.nombre ORDER BY kilos DESC;

-- Lote de eventos pendientes para el worker (varios workers no se pisan)
SELECT * FROM outbox WHERE publicado_en IS NULL ORDER BY created_at, id LIMIT 100 FOR UPDATE SKIP LOCKED;
```

## MongoDB (libro de movimientos y fichas)

| Colección | Documento | Validación (`$jsonSchema`, `validationAction: error`) | Índices |
|---|---|---|---|
| `movimientos` | `{_id: <id del outbox>, tipo, user_id, ocurrido_en, payload{…, request_id}}` | requeridos `tipo` (string), `user_id` (int/long), `ocurrido_en` (string), `payload` (object) | `{user_id: 1, ocurrido_en: -1}`, `{tipo: 1}` |
| `fichas_material` | `{_id: <id del material>, material_id, atributos{clave: valor}, actualizado_en}` | requeridos `material_id`, `atributos` (object); claves `^[a-z_]{1,40}$` validadas en la API | `_id` |

Uso visible: el **historial de movimientos** del ciudadano (paginado y filtrable por tipo) y la **ficha técnica** de
cada material (atributos libres que no justifican columnas). Consultas:

```js
db.movimientos.find({user_id: 34}).sort({ocurrido_en: -1}).skip(0).limit(15)
db.movimientos.countDocuments({"payload.request_id": "corr-1794008231-619"})   // correlación (OBS07)
db.fichas_material.updateOne({_id: 7}, {$set: {atributos: {...}}}, {upsert: true})
```

## Consistencia entre motores

- **Fuente de verdad: PostgreSQL.** Toda decisión de negocio (saldo, estados, stock) se toma ahí.
- **No hay atomicidad entre motores.** Cada cambio de estado inserta un evento en `outbox` **en la misma transacción**
  que el cambio; si la transacción falla, no hay evento.
- **Publicación idempotente.** El worker (`outbox:publicar --loop`) publica con `updateOne(_id = id del outbox,
  $setOnInsert, upsert)`: reintentar nunca duplica el documento. Solo después marca `publicado_en`.
- **Si MongoDB falla:** la API sigue aceptando escrituras, el evento queda pendiente (`intentos + 1`) y se publica al
  volver la base. Medido: entrega registrada con MongoDB caído, publicada 7 s después de su regreso, 1 documento (E11).
- **Si PostgreSQL falla:** la API responde 503 (readiness), no hay escrituras que perder; el worker reintenta con
  espera creciente sin reiniciarse (0.1.3, E11).
- **Reconstrucción de MongoDB:** como todo movimiento nace en el outbox, el historial puede regenerarse desde
  PostgreSQL volviendo a marcar eventos como pendientes.

## Estrategia de conexiones con varias réplicas

Cada proceso PHP-FPM mantiene **una conexión persistente** a PostgreSQL (`PDO::ATTR_PERSISTENT`, `DB_PERSISTENT=true`):
6 procesos × hasta 6 réplicas = 36 conexiones, más el worker y el exportador, por debajo de `max_connections = 100`.
Con una conexión por solicitud, la autenticación `scram-sha-256` saturaba la CPU de PostgreSQL (98 % de throttling,
p95 6.2 s); con conexiones persistentes se abrió 1 sesión por cada 30 solicitudes y el p95 bajó a 0.99 s (E06, E12).
Máximo observado bajo carga: 38 conexiones. MongoDB usa el pool del driver por proceso (máximo observado: 39).
