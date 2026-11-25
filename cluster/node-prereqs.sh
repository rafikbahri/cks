#!/usr/bin/env bash
# kubeadm prerequisites for an Ubuntu 24.04 node: kernel settings, containerd, kubeadm/kubelet/kubectl.
# Runs as root on every node. Usage: node-prereqs.sh <k8s minor, e.g. 1.37>
set -euo pipefail
K8S_VERSION="${1:?usage: $0 <k8s minor, e.g. 1.37>}"
export DEBIAN_FRONTEND=noninteractive

# --- Kernel: no swap, bridged traffic visible to iptables, IP forwarding
swapoff -a
sed -i '/\sswap\s/s/^[^#]/#&/' /etc/fstab
printf 'overlay\nbr_netfilter\n' > /etc/modules-load.d/k8s.conf
modprobe overlay
modprobe br_netfilter
cat > /etc/sysctl.d/k8s.conf <<'EOF'
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system >/dev/null

# --- Packages: containerd 2.x from Ubuntu, Kubernetes from pkgs.k8s.io (pinned minor)
apt-get update -qq
apt-get install -y -qq containerd apparmor-utils ca-certificates curl gpg >/dev/null
install -d -m 755 /etc/apt/keyrings
curl -fsSL "https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/Release.key" \
  | gpg --dearmor --batch --yes -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/ /" \
  > /etc/apt/sources.list.d/kubernetes.list
apt-get update -qq
apt-get install -y -qq kubelet kubeadm kubectl >/dev/null
apt-mark hold kubelet kubeadm kubectl >/dev/null

# --- containerd: systemd cgroup driver + the pause image kubeadm expects
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
PAUSE_IMAGE=$(kubeadm config images list --kubernetes-version "$(kubeadm version -o short)" | grep /pause:)
sed -i -E "s/SystemdCgroup = false/SystemdCgroup = true/; s#(sandbox(_image)? = ).*#\1'${PAUSE_IMAGE}'#" \
  /etc/containerd/config.toml
grep -q 'SystemdCgroup = true' /etc/containerd/config.toml || { echo "SystemdCgroup not set" >&2; exit 1; }
systemctl restart containerd

# --- crictl talks to containerd (used heavily in the exam)
cat > /etc/crictl.yaml <<'EOF'
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
EOF

systemctl enable kubelet >/dev/null 2>&1
echo "[$(hostname)] ready: $(kubeadm version -o short), containerd $(containerd --version | awk '{print $3}'), apparmor=$(cat /sys/module/apparmor/parameters/enabled)"
