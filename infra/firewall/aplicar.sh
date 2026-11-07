#!/bin/bash
# Uso: sudo infra/firewall/aplicar.sh <activar|revertir|exportar>   — NO se ejecuta en el laboratorio (decisión: solo documentar).
# activar: instala la zona ecocanje, la asigna a las interfaces externas y activa firewalld.
# revertir: quita las interfaces de la zona y detiene firewalld (vuelve al estado actual: sin firewall de host).
# exportar: guarda la configuración efectiva en infra/firewall/exportado-<fecha>.txt.
set -euo pipefail
IFACES=${IFACES:-"wlp61s0 ztsjsau5tt"}
case "${1:?activar|revertir|exportar}" in
activar)
  install -m 0644 "$(dirname "$0")/ecocanje.xml" /etc/firewalld/zones/ecocanje.xml
  systemctl enable --now firewalld
  firewall-cmd --reload
  for i in $IFACES; do firewall-cmd --permanent --zone=ecocanje --change-interface="$i"; done
  firewall-cmd --reload
  firewall-cmd --zone=ecocanje --list-all ;;
revertir)
  for i in $IFACES; do firewall-cmd --permanent --zone=ecocanje --remove-interface="$i" || true; done
  firewall-cmd --reload || true
  systemctl disable --now firewalld ;;
exportar)
  f="$(dirname "$0")/exportado-$(date +%Y%m%d-%H%M).txt"
  { firewall-cmd --get-active-zones; firewall-cmd --zone=ecocanje --list-all; nft list ruleset; } > "$f"; echo "$f" ;;
esac
