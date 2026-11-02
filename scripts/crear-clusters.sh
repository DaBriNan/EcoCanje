#!/bin/bash
# Uso: scripts/crear-clusters.sh <dev|prod>
set -euo pipefail
ENV=${1:?dev|prod}; K3S=$(cat infra/K3S_VERSION)
case $ENV in
  dev)  k3d cluster create dev  --servers 1 --agents 0 --image rancher/k3s:$K3S -p "8081:80@loadbalancer" -p "8444:443@loadbalancer" --k3s-arg "--secrets-encryption@server:0" --kubeconfig-switch-context=false ;;
  prod) k3d cluster create prod --servers 1 --agents 2 --image rancher/k3s:$K3S -p "8082:80@loadbalancer" -p "8445:443@loadbalancer" --k3s-arg "--secrets-encryption@server:0" --kubeconfig-switch-context=false ;;
esac
