#!/usr/bin/env bash
# Build a 2-node kubeadm cluster (control plane + worker) on Lima VMs. Safe to re-run.
# Usage: cluster/up.sh
#   EXTRA_CA=/path/ca.pem  trust an extra root CA in the VMs (TLS-inspecting corporate proxy)
#   K8S_VERSION=1.37       Kubernetes minor (default: the one the CKS exam runs)
set -euo pipefail
cd "$(dirname "$0")"

K8S_VERSION="${K8S_VERSION:-1.37}"
CP=cks-cp
WORKER=cks-worker
KUBECONFIG_OUT="${KUBECONFIG_OUT:-$HOME/.kube/cks}"

vm()      { limactl shell --workdir / "$@"; }
as_root() { local node=$1 script=$2; shift 2; vm "$node" sudo bash -s -- "$@" < "$script"; }

# --plain     no host mounts / auto port forwards: keeps ~/.kube, ~/.aws out of the lab
# lima:user-v2 VMs can reach each other (vzNAT isolates guests from one another)
ensure_vm() { # name [extra limactl flags...]
  local name=$1; shift
  case "$(limactl list --format '{{.Status}}' "$name" 2>/dev/null || true)" in
    Running) ;;
    Stopped) limactl start --tty=false "$name" ;;
    *) limactl start --name="$name" --tty=false --plain --vm-type=vz --network=lima:user-v2 \
         --cpus=2 --memory=4 --disk=20 "$@" template:ubuntu-24.04 ;;
  esac
}

echo "==> VMs (user-v2 DHCP leases persist per VM, so IPs survive restarts in any order)"
ensure_vm "$CP" --port-forward='6443:6443,static=true'
ensure_vm "$WORKER"

if [[ -n "${EXTRA_CA:-}" ]]; then
  echo "==> Trusting extra CA: $EXTRA_CA"
  for node in "$CP" "$WORKER"; do
    limactl copy "$EXTRA_CA" "$node:/tmp/corp-root-ca.crt"
    vm "$node" sudo bash -c 'install -m 644 /tmp/corp-root-ca.crt /usr/local/share/ca-certificates/corp-root-ca.crt && update-ca-certificates >/dev/null'
  done
fi

echo "==> Node prerequisites (Kubernetes v$K8S_VERSION)"
for node in "$CP" "$WORKER"; do as_root "$node" node-prereqs.sh "$K8S_VERSION"; done

if vm "$CP" sudo test -f /etc/kubernetes/admin.conf; then
  echo "==> Control plane already initialised"
else
  echo "==> kubeadm init + Cilium"
  as_root "$CP" cp-init.sh "$CP"
fi

if vm "$WORKER" sudo test -f /etc/kubernetes/kubelet.conf; then
  echo "==> Worker already joined"
else
  echo "==> Joining worker"
  # shellcheck disable=SC2046  # the join command must be word-split
  vm "$WORKER" sudo $(vm "$CP" sudo kubeadm token create --print-join-command) --node-name "$WORKER"
fi

echo "==> Kubeconfig -> $KUBECONFIG_OUT (context: cks)"
mkdir -p "$(dirname "$KUBECONFIG_OUT")"
( umask 077
  vm "$CP" sudo cat /etc/kubernetes/admin.conf \
    | sed -E 's#server: https://[^:/]+:6443#server: https://127.0.0.1:6443#' > "$KUBECONFIG_OUT" )
kubectl --kubeconfig "$KUBECONFIG_OUT" config rename-context kubernetes-admin@kubernetes cks >/dev/null

kubectl --kubeconfig "$KUBECONFIG_OUT" wait --for=condition=Ready node --all --timeout=5m
kubectl --kubeconfig "$KUBECONFIG_OUT" get nodes -o wide
