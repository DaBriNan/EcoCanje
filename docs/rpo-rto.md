# Objetivos de recuperación (definidos el 2026-11-02, antes de las pruebas de respaldo)

- RPO objetivo: 24 horas. Respaldos programados diariamente a las 02:00 (America/Mexico_City); la pérdida máxima aceptable es un día de operaciones.
- RTO objetivo: 30 minutos, contados desde el inicio de la restauración hasta que la aplicación atiende solicitudes con los datos restaurados en un espacio de recuperación aislado.
- Alcance: PostgreSQL (fuente de verdad) y MongoDB (libro de movimientos y fichas). MongoDB puede reconstruirse parcialmente desde el outbox de PostgreSQL.
- Los resultados medidos se reportan tal como salgan, aunque no cumplan el objetivo.
