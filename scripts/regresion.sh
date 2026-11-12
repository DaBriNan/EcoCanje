#!/bin/bash
source "$(dirname "$0")/ev.sh"; cd "$EV_RAIZ" || exit 1
ev E09 "Autorizacion por rol en la API"           "200, 401, 403 y 401"                 tests/roles.sh;    sleep 61
ev E03 "Flujo de negocio entregas y canjes"       "todas las verificaciones OK"         tests/flujo.sh;    sleep 61
ev E03 "CRUD de catalogo, fichas y validaciones"  "todas las verificaciones OK"         tests/catalogo.sh; sleep 61
ev E04 "Recuperacion del outbox sin duplicados"   "mismo numero de documentos tras el reintento" tests/outbox.sh
