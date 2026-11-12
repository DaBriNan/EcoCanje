#!/bin/bash
# Uso: tests/rbac.sh <dev|prod>  — E09: RBAC por función con certificados de cliente reales (scripts/crear-usuario.sh).
# Las acciones permitidas que modificarían algo usan --dry-run=server: la API autoriza completo pero no persiste.
ENV=${1:?dev|prod}; CTX=k3d-$ENV; D=$HOME/.local/share/ecocanje-pki/usuarios; ok=0; fail=0
chk() { if [ "$2" = "$3" ]; then echo "OK    $1 -> $2"; ok=$((ok+1)); else echo "FALLA $1 -> $2 (esperado $3)"; fail=$((fail+1)); fi; }
como() { local u=$1; shift; local e; e=$(kubectl --kubeconfig "$D/$ENV-$u.kubeconfig" "$@" 2>&1 >/dev/null) && echo permitido \
  || { echo "$e" | grep -q -i forbidden && echo denegado || echo "error: $(echo "$e" | head -1)"; }; }
for x in "ana lectura" "beto despliegue" "caro operaciones"; do set -- $x; scripts/crear-usuario.sh "$ENV" "$1" "$2" | head -1; done
# "rollout restart" no acepta --dry-run: se usa el mismo parche que aplica (anotación restartedAt)
REINICIO=(patch deploy/backend --dry-run=server -p "{\"spec\":{\"template\":{\"metadata\":{\"annotations\":{\"kubectl.kubernetes.io/restartedAt\":\"$(date -Is)\"}}}}}")
P=$(kubectl --context "$CTX" -n ecocanje get pod -l app=backend -o jsonpath='{.items[0].metadata.name}')

echo "== ana (ecocanje:lectura)"
chk "listar pods"                         "$(como ana get pods)" permitido
chk "leer logs del backend"               "$(como ana logs "$P" -c nginx --tail=1)" permitido
chk "leer Secrets"                        "$(como ana get secrets)" denegado
chk "borrar un pod"                       "$(como ana delete pod "$P" --dry-run=server)" denegado
chk "reiniciar el backend"                "$(como ana "${REINICIO[@]}")" denegado
chk "exec en el backend"                  "$(como ana exec "$P" -c php -- true)" denegado
chk "ver pods de otro namespace (monitoring)" "$(como ana -n monitoring get pods)" denegado
echo "== beto (ecocanje:despliegue)"
chk "reiniciar el backend"                "$(como beto "${REINICIO[@]}")" permitido
chk "escalar el backend"                  "$(como beto scale deploy/backend --replicas=3 --dry-run=server)" permitido
chk "crear un Job desde el CronJob"       "$(como beto create job rbac-prueba --from=cronjob/respaldo-postgres --dry-run=server)" permitido
chk "leer Secrets"                        "$(como beto get secret app-runtime)" denegado
chk "exec en el backend"                  "$(como beto exec "$P" -c php -- true)" denegado
chk "borrar una NetworkPolicy"            "$(como beto delete networkpolicy denegar-todo --dry-run=server)" denegado
chk "borrar un PVC"                       "$(como beto delete pvc respaldos --dry-run=server)" denegado
chk "modificar RBAC"                      "$(como beto delete rolebinding lectura --dry-run=server)" denegado
echo "== caro (ecocanje:operaciones)"
chk "exec en el backend (diagnóstico)"    "$(como caro exec "$P" -c php -- true)" permitido
chk "leer Secrets"                        "$(como caro get secrets)" denegado
chk "borrar una NetworkPolicy"            "$(como caro delete networkpolicy denegar-todo --dry-run=server)" denegado
chk "cambiar la cuota del namespace"      "$(como caro delete resourcequota cuota-ecocanje --dry-run=server)" denegado
echo "Resultado: $ok correctas, $fail fallidas"; exit $((fail>0))
