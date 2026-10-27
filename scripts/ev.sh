#!/bin/bash
# Uso:  source scripts/ev.sh
#       ev E03 "Descripción" "Resultado esperado" comando arg1 arg2 ...
# Ejecutar siempre desde ~/ecocanje. EV_AMBIENTE="prod" fuerza el nombre del ambiente.
unalias dc 2>/dev/null
EV_RAIZ="${EV_RAIZ:-$HOME/ecocanje}"
EV_DIR="$EV_RAIZ/docs/evidencias"

dc()  { docker compose --env-file "$EV_RAIZ/.env.compose" -f "$EV_RAIZ/docker-compose.yml" "$@"; }
art() { dc exec -u "$(id -u):$(id -g)" -e HOME=/tmp api php artisan "$@"; }
cmp() { dc exec -u "$(id -u):$(id -g)" -e HOME=/tmp api composer "$@"; }

redact() {
  sed -E \
    -e 's/(Bearer )[A-Za-z0-9|._-]+/\1***/g' \
    -e 's/("token":")[^"]+/\1***/g' \
    -e 's/("password":")[^"]+/\1***/Ig' \
    -e 's/((PASSWORD|PASS|SECRET|TOKEN|KEY)[A-Z_]*=)[^[:space:]]+/\1***/Ig'
}

ev() {
  local id="$1" desc="$2" esp="$3" ts slug f ctx amb rc estado obs commit
  shift 3
  ts=$(date +%Y%m%d-%H%M%S)
  slug=$(echo "$desc" | iconv -f utf-8 -t ascii//TRANSLIT 2>/dev/null | tr 'A-Z ' 'a-z-' | tr -cd 'a-z0-9-' | cut -c1-40)
  f="$EV_DIR/$id-$slug-$ts.txt"
  ctx=$(kubectl config current-context 2>/dev/null || echo "compose-local")
  case "$1" in kubectl*|helm*|k3d*) amb="${EV_AMBIENTE:-$ctx}";; *) amb="${EV_AMBIENTE:-compose-local}";; esac
  commit="$(git -C "$EV_RAIZ" rev-parse --short HEAD 2>/dev/null)"
  git -C "$EV_RAIZ" diff --quiet 2>/dev/null || commit="$commit+cambios"
  {
    echo "ID: $id"; echo "Descripción: $desc"; echo "Fecha: $(date -Is)"
    echo "Ambiente: $amb"; echo "Host: $(hostname)"; echo "Commit: $commit"
    echo "Comando: $*"; echo "Esperado: $esp"; echo "----- salida -----"
  } | redact > "$f"
  "$@" 2>&1 | redact | tee -a "$f"
  rc=${PIPESTATUS[0]}
  [ "$rc" -eq 0 ] && estado="OK" || estado="FALLA($rc)"
  obs=$(grep -v '^[[:space:]]*$' "$f" | tail -n1 | tr '|' '/' | cut -c1-90)
  echo "----- fin: $estado -----" >> "$f"
  [ -f "$EV_DIR/INDEX.md" ] || printf '| ID | Fecha | Ambiente | Descripción | Esperado | Observado (última línea) | Resultado | Archivo |\n|---|---|---|---|---|---|---|---|\n' > "$EV_DIR/INDEX.md"
  printf '| %s | %s | %s | %s | %s | %s | %s | [%s](%s) |\n' "$id" "$(date '+%F %T')" "$amb" "$desc" "$esp" "$obs" "$estado" "$(basename "$f")" "$(basename "$f")" >> "$EV_DIR/INDEX.md"
  echo "- $(date -Is) [$amb] \`$*\` → $estado ($id)" | redact >> "$EV_RAIZ/docs/manual/comandos-ejecutados.md"
  echo ">>> evidencia guardada: $f ($estado)"
  return "$rc"
}

ev_historial() { history | tail -300 | redact > "$EV_DIR/historial-$(date +%F).txt"; echo "historial guardado"; }
