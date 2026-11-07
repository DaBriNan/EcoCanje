#!/bin/bash
# Uso: scripts/crear-clusters.sh <dev|prod>
set -euo pipefail
# API y entrada publicadas solo en 127.0.0.1: Docker se salta el firewall del host, así que el control va en el origen.
ENV=${1:?dev|prod}; K3S=$(cat infra/K3S_VERSION)
case $ENV in
  dev)  k3d cluster create dev  --servers 1 --agents 0 --image rancher/k3s:$K3S --api-port 127.0.0.1:6550 -p "127.0.0.1:8081:80@loadbalancer" -p "127.0.0.1:8444:443@loadbalancer" --k3s-arg "--secrets-encryption@server:0" --kubeconfig-switch-context=false ;;
  prod) k3d cluster create prod --servers 1 --agents 2 --image rancher/k3s:$K3S --api-port 127.0.0.1:6551 -p "127.0.0.1:8082:80@loadbalancer" -p "127.0.0.1:8445:443@loadbalancer" --k3s-arg "--secrets-encryption@server:0" --kubeconfig-switch-context=false ;;
esac
