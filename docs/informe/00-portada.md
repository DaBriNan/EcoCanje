---
title: "EcoCanje — Expediente técnico (D01–D10)"
subtitle: "Práctica individual Kubernetes: desarrollo y producción · Infraestructura de Servicios, ITM"
author: "DaBriNan"
date: "Noviembre de 2026 · versión del código v1.0.0"
lang: es-MX
---

# Índice del expediente

| Documento | Contenido | Archivos principales del repositorio |
|---|---|---|
| D01 | Ficha, reglas de negocio, requerimientos funcionales y no funcionales con criterios de aceptación | `backend/app`, `tests/` |
| D02 | Investigación de Kubernetes y diez decisiones de arquitectura | `infra/`, `scripts/crear-clusters.sh` |
| D03 | Diagramas de aplicación, secuencia, implementación y comunicación; inventario y capacidad | `docs/diagramas/*.mmd` |
| D04 | Modelos y diccionarios de PostgreSQL y MongoDB, migraciones, consistencia y conexiones | `backend/database/migrations`, `PrepararMongo.php` |
| D05 | Manual de instalación desde cero y verificación | `scripts/bootstrap.sh`, `README.md` |
| D06 | Seguridad: controles, RBAC, cuentas de BD, flujos, firewall, secretos, vulnerabilidades, riesgos | `infra/base/rbac.yaml`, `redes.yaml`, `infra/firewall/` |
| D07 | Publicación, promoción, actualización, rollback y accesos | `scripts/actualizacion.sh`, `promover-frontend.sh`, `.github/workflows/ci.yml` |
| D08 | Operación, observabilidad, alertas y manual de incidentes | `infra/observabilidad/`, `scripts/prom.sh`, `loki.sh` |
| D09 | Respaldos, restauración y continuidad con RPO y RTO medidos | `infra/base/respaldos.yaml`, `scripts/restaurar.sh` |
| D10 | Plan de pruebas, matriz E01–E14, hallazgos, conclusiones y limitaciones | `docs/evidencias/INDEX.md` |

Las evidencias citadas (E01–E14, OBS, SUP, DEP, SEC, INC) están en `docs/evidencias/`, con su salida completa y su
fila en `INDEX.md`.
