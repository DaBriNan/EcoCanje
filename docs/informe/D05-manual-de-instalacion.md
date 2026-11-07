# D05. Manual de instalación desde cero

Este manual reconstruye **dev** y **prod** en un equipo limpio. El camino automático es `scripts/bootstrap.sh`; cada
fase indica los comandos equivalentes para ejecutarla a mano. Ningún secreto está en el repositorio: se generan dentro
de cada clúster durante la instalación.

## 1. Prerrequisitos del host

| Componente | Versión usada | Para qué |
|---|---|---|
| Linux x86_64 | Fedora 44, kernel 7.2 | host |
| Docker | 29.9.3 | nodos de k3d y construcción de imágenes |
| k3d | v5 (`k3d version`) | clústeres k3s en contenedores |
| k3s | v1.36.5 (`infra/K3S_VERSION`) | distribución de Kubernetes |
| kubectl / helm | cliente compatible con 1.36 / Helm 4 | administración y charts |
| skopeo | cualquiera | consultar etiquetas y digests de imágenes |
| mkcert | con su CA instalada (`mkcert -install`) | certificados TLS locales |
| python3 + PyYAML, openssl, bc | de la distribución | scripts |

```bash
# Nombres locales de ambos ambientes (requiere sudo una sola vez)
echo "127.0.0.1 dev.ecocanje.test prod.ecocanje.test" | sudo tee -a /etc/hosts
mkcert -install                       # CA local, solo en este equipo
git clone https://github.com/DaBriNan/EcoCanje.git ecocanje && cd ecocanje && git checkout v1.0.0
scripts/validar.sh                    # validación estática antes de tocar clústeres
```

## 2. Instalación automática

```bash
scripts/bootstrap.sh
```

El script se detiene si `k3d-dev` o `k3d-prod` ya existen (nunca borra) y si falta cualquier prerrequisito. Al final
imprime el tiempo de cada fase y termina con código distinto de 0 si alguna verificación falla.

## 3. Fases y comandos equivalentes

| Fase | Qué hace | Comandos equivalentes |
|---|---|---|
| 0 | Prerrequisitos, `/etc/hosts`, CA de mkcert, gancho pre-commit | `cp docs/manual/gancho-pre-commit.sh .git/hooks/pre-commit` (y `gancho-excluir-secretos.txt`) |
| 1 | Imágenes: usa las existentes o las construye desde la revisión actual | `docker build -f backend/Dockerfile.prod --build-arg MONGO_EXT=$(cat infra/MONGODB_EXT_VERSION) --build-arg APP_VERSION=0.1.3 -t ecocanje-backend:0.1.3 backend`; `docker build --build-arg VITE_VERSION=0.1.5 -t ecocanje-frontend:0.1.5 frontend` |
| 2 | Clústeres: dev (1 nodo) y prod (1 server + 2 workers), API y entrada solo en 127.0.0.1, cifrado de Secrets en reposo | `scripts/crear-clusters.sh dev`; `scripts/crear-clusters.sh prod` |
| 3 | Importar imágenes en cada clúster y compararlas con el id aprobado | `k3d image import ecocanje-backend:0.1.3 ecocanje-frontend:0.1.5 -c <amb>`; `scripts/verificar-imagen.sh <amb> 0.1.3`; `IMG=ecocanje-frontend scripts/verificar-imagen.sh <amb> 0.1.5` |
| 4 | Aplicación: namespace, Secrets generados, TLS, migraciones y semilla, despliegue | `scripts/desplegar.sh <amb>` (llama a `crear-secretos.sh` y `crear-tls.sh`, recrea el Job `migraciones`, aplica `infra/<amb>` con Kustomize) |
| 5 | Observabilidad en prod | `kubectl apply -f infra/observabilidad/namespaces.yaml`; `scripts/crear-secretos-monitoreo.sh k3d-prod`; `helm upgrade --install kps prometheus-community/kube-prometheus-stack --version 92.17.1 -n monitoring -f infra/observabilidad/kps-values.yaml`; `helm upgrade --install node-exporter prometheus-community/prometheus-node-exporter --version 4.60.1 -n monitoring-nodos -f infra/observabilidad/node-exporter-values.yaml`; `scripts/observabilidad.sh prod` |
| 6 | Logs en prod | `scripts/logs.sh prod` (Loki 19.1.1 y Alloy 1.14.2; valida la configuración de Alloy antes) |
| 7 | Verificación | ver sección 4 |

Accesos de personas (RBAC por función, D06/D07), después de la instalación:
`scripts/crear-usuario.sh prod <usuario> <lectura|despliegue|operaciones>` (kubeconfig en
`~/.local/share/ecocanje-pki/usuarios/`, permisos 600).

## 4. Verificación de cada ambiente

| Verificación | Comando | Esperado |
|---|---|---|
| Nodos y Pods | `kubectl --context k3d-<amb> get nodes`; `source scripts/ev.sh; pods_sanos k3d-<amb>` | nodos Ready; todos los Pods Running/Completed |
| HTTPS, versión e interfaz | `curl https://<amb>.ecocanje.test:<puerto>/api/health/live`; `…/api/health/ready`; `…/` | `{"status":"ok","version":"0.1.3"}`, 200, 200 |
| Funcional por API | `scripts/probar.sh <amb> tests/roles.sh`, `tests/flujo.sh`, `tests/catalogo.sh` (esperar 61 s entre pruebas: límite de inicio de sesión) | todas correctas |
| Funcional por interfaz | `scripts/probar.sh <amb> tests/interfaz/correr.sh` | 24 correctas |
| Red y exposición | `tests/netpol-app.sh <amb>`, `tests/netpol-frontend.sh <amb>`, `tests/exposicion.sh` | todo lo no permitido, bloqueado |
| RBAC | `tests/rbac.sh <amb>` | 19 correctas |
| Métricas y alertas (prod) | `scripts/prom.sh prod 'up == 0'`; `scripts/prom.sh prod 'sum(prometheus_rule_group_rules{rule_group=~".*ecocanje.*"}) == 8'`; `scripts/verificar-metricas.sh prod` | sin objetivos caídos; 8 reglas; 44 métricas existentes |
| Logs (prod) | `scripts/loki.sh prod 'sum by (app) (count_over_time({namespace="ecocanje"}[5m]))'` | líneas de backend, frontend, bases y worker |
| Datos | `scripts/estado-datos.sh k3d-<amb>` | usuarios y entregas semilla; outbox pendientes 0 |

## 5. Tiempos medidos (E14)

| Corrida | Fecha | Cambio | Total |
|---|---|---|---|
| 1 | 2026-11-06 17:59 | primera reconstrucción completa | 759 s |
| 2 | 2026-11-06 18:21 | publicación solo en 127.0.0.1 | 671 s |
| 3 | 2026-11-06 18:59 | k3s v1.36.1 → v1.36.5 | 638 s |

Fases más largas: aplicación en prod (79–198 s, espera de bases y migraciones) y observabilidad (178–194 s). Las tres
corridas terminaron verificadas sin pasos manuales adicionales. Diferencias registradas en las evidencias E14.

## 6. Problemas conocidos al instalar u operar en este host

| Síntoma | Causa | Solución |
|---|---|---|
| Workers `NotReady` tras reiniciar el host; `docker logs k3d-prod-agent-N` muestra `failed to find interface with specified node ip` | Docker intercambió las IP de los agentes | `docker restart k3d-prod-agent-0 k3d-prod-agent-1` (E11, 5 nov) |
| HPA sin escalar y evento `FailedGetScale: Unauthorized` tras suspender el equipo | salto de reloj al reanudar | transitorio (minutos); verificar con `kubectl describe hpa backend` |
| Prueba larga con resultados mezclados | el equipo se suspendió | `ev` y `carga.sh` usan `systemd-inhibit`; mantener el equipo con corriente |
| `ErrImageNeverPull` | imagen no importada en el clúster | fase 3 (`k3d image import`) |
| Navegador rechaza el certificado | CA de mkcert no instalada en ese navegador | `mkcert -install` con el navegador cerrado |
