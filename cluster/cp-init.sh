#!/usr/bin/env bash
# kubeadm init + Cilium CNI on the control-plane node. Runs as root. Usage: cp-init.sh <node-name>
set -euo pipefail
NODE_NAME="${1:?usage: $0 <node-name>}"
POD_CIDR="${POD_CIDR:-10.244.0.0/16}"
CP_IP=$(ip -4 -o addr show eth0 | awk '{print $4}' | cut -d/ -f1)

# 127.0.0.1 SAN: the Mac reaches the API server through a Lima port forward on localhost:6443
kubeadm init \
  --node-name "$NODE_NAME" \
  --apiserver-advertise-address "$CP_IP" \
  --apiserver-cert-extra-sans "127.0.0.1,localhost" \
  --pod-network-cidr "$POD_CIDR" \
  --kubernetes-version "$(kubeadm version -o short)"

# kubectl for the default VM user
VM_USER="${SUDO_USER:-lima}"
VM_HOME=$(getent passwd "$VM_USER" | cut -d: -f6)
install -d -o "$VM_USER" -g "$VM_USER" "$VM_HOME/.kube"
install -m 600 -o "$VM_USER" -g "$VM_USER" /etc/kubernetes/admin.conf "$VM_HOME/.kube/config"
export KUBECONFIG=/etc/kubernetes/admin.conf

# Cilium CLI (checksum-verified), then Cilium using the per-node podCIDRs kubeadm allocates
ARCH=$(dpkg --print-architecture)
CILIUM_CLI_VERSION=$(curl -fsSL https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
cd "$(mktemp -d)"
curl -fsSL --remote-name-all \
  "https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-${ARCH}.tar.gz"{,.sha256sum}
sha256sum --check --quiet "cilium-linux-${ARCH}.tar.gz.sha256sum"
tar -xzf "cilium-linux-${ARCH}.tar.gz" -C /usr/local/bin
cilium install --set ipam.mode=kubernetes --set operator.replicas=1
cilium status --wait --wait-duration 5m
