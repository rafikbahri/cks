#!/usr/bin/env bash
# Destroy the lab built by up.sh: both Lima VMs and the lab kubeconfig. Safe to re-run.
# Usage: cluster/down.sh
#   KUBECONFIG_OUT=...  same override as up.sh (default: ~/.kube/cks)
set -euo pipefail

CP=cks-cp
WORKER=cks-worker
KUBECONFIG_OUT="${KUBECONFIG_OUT:-$HOME/.kube/cks}"

# Captured first, then grepped: `limactl list | grep -q` can die of SIGPIPE under pipefail
INSTANCES=$(limactl list --quiet 2>/dev/null || true)

for vm in "$WORKER" "$CP"; do
  if grep -qx "$vm" <<<"$INSTANCES"; then
    echo "==> Deleting VM $vm"
    limactl delete --force "$vm" # --force stops it first if running; the disk is discarded anyway
  else
    echo "==> VM $vm not found"
  fi
done

# Only remove a kubeconfig that up.sh wrote (a single "cks" context), never a shared one
if [[ -f "$KUBECONFIG_OUT" ]]; then
  if [[ "$(kubectl --kubeconfig "$KUBECONFIG_OUT" config get-contexts -o name 2>/dev/null)" == cks ]]; then
    rm "$KUBECONFIG_OUT"
    echo "==> Removed $KUBECONFIG_OUT"
  else
    echo "==> Kept $KUBECONFIG_OUT: it holds contexts other than 'cks'" >&2
  fi
fi

echo "==> Done (Lima image cache kept for a faster rebuild)"
