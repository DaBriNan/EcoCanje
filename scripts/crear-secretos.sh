#!/bin/bash
# Uso: scripts/crear-secretos.sh <contexto>  (crea los Secrets si no existen; no imprime valores)
set -euo pipefail
CTX="${1:?uso: crear-secretos.sh <contexto>}"; NS=ecocanje
K() { kubectl --context "$CTX" -n "$NS" "$@"; }
gen() { openssl rand -base64 24 | tr -d '/+=' | cut -c1-24; }
existe() { K get secret "$1" >/dev/null 2>&1; }
val() { K get secret "$1" -o "jsonpath={.data.$2}" | base64 -d; }
URI="@mongo:27017/ecocanje?authSource=ecocanje&serverSelectionTimeoutMS=3000&connectTimeoutMS=3000"

existe postgres-credenciales || { K create secret generic postgres-credenciales \
  --from-literal=admin="$(gen)" --from-literal=migrador="$(gen)" --from-literal=app="$(gen)" \
  --from-literal=backup="$(gen)" --from-literal=monitor="$(gen)" >/dev/null; echo "creado postgres-credenciales"; }
existe mongo-credenciales || { K create secret generic mongo-credenciales \
  --from-literal=root="$(gen)" --from-literal=migrador="$(gen)" --from-literal=app="$(gen)" \
  --from-literal=backup="$(gen)" --from-literal=monitor="$(gen)" >/dev/null; echo "creado mongo-credenciales"; }
existe app-runtime || { K create secret generic app-runtime \
  --from-literal=app-key="base64:$(openssl rand -base64 32)" \
  --from-literal=db-pass="$(val postgres-credenciales app)" \
  --from-literal=mongodb-uri="mongodb://ecocanje_app:$(val mongo-credenciales app)$URI" >/dev/null; echo "creado app-runtime"; }
existe app-migracion || { K create secret generic app-migracion \
  --from-literal=db-pass="$(val postgres-credenciales migrador)" \
  --from-literal=mongodb-uri="mongodb://ecocanje_migrador:$(val mongo-credenciales migrador)$URI" \
  --from-literal=seed-pass="$(gen)" >/dev/null; echo "creado app-migracion"; }
K get secret -o go-template='{{range .items}}{{.metadata.name}}: {{range $k,$v := .data}}{{$k}} {{end}}{{"\n"}}{{end}}'
