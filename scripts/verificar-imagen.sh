#!/bin/bash
# Uso: [IMG=ecocanje-frontend] scripts/verificar-imagen.sh <dev|prod> [etiqueta] [--registrar]   (IMG por defecto: ecocanje-backend)
# Todos los nodos del ambiente deben tener el mismo id; con --registrar se guarda como "imagen aprobada",
# sin la opcion se compara contra el id registrado (promocion de la misma imagen entre ambientes).
ENV=${1:?dev|prod}; TAG=${2:-0.1.1}; IMG=${IMG:-ecocanje-backend}; rc=0; ref=""
[ "$IMG" = ecocanje-backend ] && REG=infra/imagen-aprobada-$TAG.id || REG=infra/imagen-aprobada-${IMG#ecocanje-}-$TAG.id
for n in $(docker ps --format '{{.Names}}' | grep -E "^k3d-$ENV-(server|agent)-[0-9]+$" | sort); do
  ID=$(docker exec "$n" crictl images 2>/dev/null | awk -v t="$TAG" -v i="$IMG" '$1 ~ ("/" i "$") && $2==t {print $3}')
  [ -z "$ref" ] && ref="$ID"
  if [ -n "$ID" ] && [ "$ID" = "$ref" ]; then echo "OK    $n -> $ID"; else echo "FALLA $n -> '${ID:-sin imagen}' (referencia $ref)"; rc=1; fi
done
if [ "${3:-}" = "--registrar" ] && [ $rc -eq 0 ]; then echo "$ref" > "$REG"; echo "imagen aprobada registrada en $REG: $ref"
elif [ -f "$REG" ]; then
  if [ "$(cat "$REG")" = "$ref" ]; then echo "OK    identica a la imagen aprobada ($(cat "$REG"))"; else echo "FALLA distinta de la aprobada ($(cat "$REG"))"; rc=1; fi
fi
exit $rc
