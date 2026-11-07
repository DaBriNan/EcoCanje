#!/bin/sh
EXC="$(git rev-parse --git-dir)/hooks/excluir-secretos.txt"
[ -s "$EXC" ] || { echo "Falta $EXC: el gancho no puede filtrar falsos positivos"; exit 1; }
if git diff --cached -U0 -- . ':(exclude)*.example' ':(exclude)*.htaccess' ':(exclude)*.lock' \
 | grep -E '^\+' \
 | grep -Ei '(password|secret|token|apikey)[A-Za-z_]*[[:space:]]*[:=][[:space:]]*[^[:space:]$<{]' \
 | grep -Eiv '[:=][[:space:]]*(null|false|true)?[[:space:]]*$' \
 | grep -Eiv '::class|secretName|secretKeyRef|_FILE|existingSecret|passwordKey|userKey|openssl rand|\\?\$\(cat |__ENV\.|\.json\(.token.\)|[:=][[:space:]]*\*\*\*' \
 | grep -Eiv -f "$EXC"; then
  echo "Posible secreto en el commit"; exit 1
fi
