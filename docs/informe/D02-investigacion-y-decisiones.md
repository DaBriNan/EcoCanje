# D02. Investigación de Kubernetes y decisiones de arquitectura

## Conceptos aplicados

- **Clúster, nodo, control plane y worker.** k3s empaqueta API server, scheduler, controller-manager y etcd/kine en
  un solo binario. En prod el control plane corre en `k3d-prod-server-0`; las cargas de la aplicación se fijan a los
  workers con afinidad de nodo (`node-role.kubernetes.io/control-plane DoesNotExist`).
- **Deployment, StatefulSet, Job y CronJob.** Backend, frontend y worker del outbox son Deployments sin estado; las
  bases son StatefulSets con un PVC por réplica; las migraciones son un Job único por despliegue y los respaldos,
  CronJobs.
- **Service frente a publicación.** Un Service `ClusterIP` (backend, frontend, postgres, mongo) solo reparte
  conexiones entre endpoints **dentro** del clúster. Lo que publica tráfico fuera es el controlador de entrada
  (Traefik) detrás del balanceador de k3d (`k3d-*-serverlb`, un contenedor nginx en el host que reenvía los puertos
  publicados al Service `LoadBalancer` de Traefik, respaldado por ServiceLB/klipper-lb de k3s). Un recurso Ingress
  sin su controlador no publica nada.
- **IP externa en laboratorio.** No hay IP pública: k3d publica los puertos del balanceador en `127.0.0.1` del host
  y `/etc/hosts` resuelve `dev.ecocanje.test` y `prod.ecocanje.test` a esa dirección.
- **HPA y recursos.** El HPA calcula el porcentaje de CPU sobre los *requests* (backend: 100m + 20m por Pod); crea
  Pods, no máquinas: con 6 réplicas se alcanzó el límite de CPU de los Pods (D10, E06).
- **PDB.** Regula desalojos voluntarios (drain), no fallos imprevistos: no evita la caída de un nodo.

## Decisiones

| # | Decisión | Alternativa descartada | Motivo | Costo | Limitación |
|---|---|---|---|---|---|
| ADR-01 | **Distribución: k3s v1.36.5 en k3d** (contenedores Docker como nodos), dos clústeres en el mismo host | minikube; kubeadm en VMs | k3d crea clústeres multinodo reales (1+2) en segundos y reproducibles por script; k3s es una distribución certificada y ligera | 0 (software libre); comparte CPU/RAM del host | Los "nodos" comparten kernel y disco: la falla del host tumba ambos ambientes. Tras reiniciar o suspender el host, Docker puede intercambiar IP de agentes (incidente E11) |
| ADR-02 | **CNI: flannel (VXLAN) + kube-router** para NetworkPolicy, ambos integrados en k3s | Calico; Cilium | Hace cumplir NetworkPolicy sin componentes extra; probado A/B (E08) | Ninguno adicional | kube-router rechaza con REJECT y programa reglas con un breve retraso para Pods nuevos (observado en E10: un Job falló por *Connection refused* a los 2 s) |
| ADR-03 | **Entrada: Ingress con Traefik 3.7** (incluido en k3s), TLS con certificado de la CA local (mkcert) | Gateway API; ingress-nginx | Traefik viene mantenido y versionado con k3s (sube con la versión de k3s: 3.6.13 → 3.7.13 en v1.36.5); Ingress basta para dos rutas (`/` y `/api`) | Ninguno | Gateway API daría roles y rutas más expresivas; el certificado solo es confiable en el host con la CA instalada |
| ADR-04 | **Persistencia: local-path-provisioner** (StorageClass `local-path`) | Longhorn; NFS | Incluido en k3s, sin dependencias | Ninguno | El volumen queda atado al nodo: con el drain de un worker su base no puede moverse y queda detenida hasta el uncordon (E11). En producción real: almacenamiento replicado o base con réplicas |
| ADR-05 | **Motores de datos: PostgreSQL (fuente de verdad) + MongoDB** (movimientos y fichas), sincronizados con **outbox idempotente** | Escritura doble en ambos motores; solo PostgreSQL con JSONB | Las operaciones de puntos requieren transacciones y llaves foráneas; el historial y las fichas son documentos flexibles. El outbox evita suponer atomicidad entre motores | Un worker adicional y latencia de segundos en el historial | Una instancia por motor (sin réplicas): cada base es punto único de fallo |
| ADR-06 | **Observabilidad: kube-prometheus-stack + exportadores de ambas bases; Loki + Alloy para logs** | ELK/EFK; Promtail | Pila estándar con CRD (PodMonitor, PrometheusRule) y panel como código; Alloy reemplaza a Promtail (obsoleto) y lee por la API sin privilegios | ~1 core y ~1.5 GiB en prod | Monitoreo dentro del mismo clúster: si caen los workers, cae también (incidente del 5 nov) |
| ADR-07 | **Configuración declarativa: Kustomize** (base + overlays dev/prod) y Helm solo para charts de terceros, con versiones fijadas | Charts propios de Helm | Diferencias entre ambientes visibles en un parche pequeño; sin plantillas | Ninguno | Los valores sensibles nunca van en Kustomize: los crean scripts en cada clúster |
| ADR-08 | **SPA servida en el mismo origen** (`/` frontend, `/api` backend) con token Bearer en `sessionStorage` | Cookies de sesión con CSRF; dominios separados con CORS | Sin CORS ni CSRF; el token se pierde al cerrar la pestaña y expira en 8 h | Ninguno | Un XSS podría leer el token; se mitiga con CSP estricta (`script-src 'self'`) |
| ADR-09 | **Conexiones persistentes a PostgreSQL** (PDO) por proceso PHP-FPM | Una conexión por solicitud; PgBouncer | La autenticación scram por solicitud saturó la CPU de PostgreSQL (E06, 0.1.1) | Hasta 6 réplicas × 6 procesos = 36 conexiones de 100 | Tras reiniciar PostgreSQL las conexiones rotas se descartan al primer error (el worker lo hace explícitamente) |
| ADR-10 | **Publicación solo en 127.0.0.1** de la API de Kubernetes y la entrada | Firewall del host como único control | Docker inserta sus reglas antes que firewalld: publicar en 0.0.0.0 dejaba la API alcanzable desde la LAN y la VPN (E08) | Ninguno | Acceso solo desde el propio host; el firewall de host queda documentado (D06) |
