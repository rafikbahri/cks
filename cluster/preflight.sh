#!/usr/bin/env bash
# Check that this Mac can run the lab built by up.sh. Read-only: changes nothing. Safe to re-run.
# Usage: cluster/preflight.sh
#   K8S_VERSION=1.37       same override as up.sh (kubectl must be within one minor of it)
#   EXTRA_CA=/path/ca.pem  same override as up.sh (checked for a readable PEM certificate)
set -euo pipefail

K8S_VERSION="${K8S_VERSION:-1.37}"
CP=cks-cp
MIN_MACOS=13.5 # Lima's vz driver
MIN_LIMA=2.0.0 # first release with `limactl start --port-forward`, used by up.sh
VMS=2 VM_CPUS=2 VM_MEM_GIB=4 VM_DISK_GIB=20 # keep in sync with ensure_vm in up.sh
BUNDLE="brew bundle --file $(cd "$(dirname "$0")/.." && pwd)/.Brewfile"

FAILED=0
ok()   { echo "  ok    $*"; }
warn() { echo "  warn  $*" >&2; }
fail() { echo "  FAIL  $*" >&2; FAILED=1; }

# version_ge A B: dotted version A >= B (pre-release suffixes like -rc.1 ignored)
version_ge() {
  local IFS=. i
  local -a a=(${1%%[-+]*}) b=(${2%%[-+]*})
  for ((i = 0; i < ${#b[@]}; i++)); do
    if (( 10#${a[i]:-0} != 10#${b[i]} )); then (( 10#${a[i]:-0} > 10#${b[i]} )); return; fi
  done
}

echo "==> macOS"
[[ "$(uname -s)" == Darwin ]] || { fail "not macOS ($(uname -s))"; exit 1; }
MACOS=$(sw_vers -productVersion)
if version_ge "$MACOS" "$MIN_MACOS"; then ok "macOS $MACOS ($(uname -m))"
else fail "macOS $MACOS: Lima's vz driver needs $MIN_MACOS+"; fi

echo "==> Tools"
if command -v brew >/dev/null; then ok "Homebrew $(brew --version | awk 'NR==1{print $2}')"
else warn "Homebrew not found: get it from https://brew.sh, or install lima and kubectl by hand"; fi

if command -v limactl >/dev/null; then
  LIMA=$(limactl --version | awk '{print $NF}'); LIMA=${LIMA#v}
  if version_ge "$LIMA" "$MIN_LIMA"; then ok "Lima $LIMA"
  else fail "Lima $LIMA: up.sh needs $MIN_LIMA+ (brew upgrade lima)"; fi
else
  fail "limactl not found ($BUNDLE)"
fi

if command -v kubectl >/dev/null; then
  KUBECTL=$(kubectl version --client 2>/dev/null | awk '/^Client Version/{print $3}'); KUBECTL=${KUBECTL#v}
  MINOR=$(cut -d. -f2 <<<"$KUBECTL") WANT=${K8S_VERSION#*.}
  if [[ "$MINOR" =~ ^[0-9]+$ ]] && (( MINOR >= WANT - 1 && MINOR <= WANT + 1 )); then ok "kubectl $KUBECTL"
  else fail "kubectl ${KUBECTL:-unknown}: must be within one minor of the v$K8S_VERSION cluster (version skew policy)"; fi
else
  fail "kubectl not found ($BUNDLE)"
fi

echo "==> Host resources ($VMS VMs x ${VM_CPUS} CPU, ${VM_MEM_GIB} GiB RAM, ${VM_DISK_GIB} GiB disk)"
CPUS=$(sysctl -n hw.ncpu)
if (( CPUS >= VMS * VM_CPUS )); then ok "$CPUS CPUs"
else fail "$CPUS CPUs: the VMs alone take $((VMS * VM_CPUS))"; fi

MEM_GIB=$(( $(sysctl -n hw.memsize) / 1024 ** 3 )) NEED_MEM=$((VMS * VM_MEM_GIB))
if (( MEM_GIB < NEED_MEM )); then fail "$MEM_GIB GiB RAM: the VMs alone take $NEED_MEM GiB"
elif (( MEM_GIB < NEED_MEM + 4 )); then warn "$MEM_GIB GiB RAM: the VMs take $NEED_MEM GiB, leaving little for macOS"
else ok "$MEM_GIB GiB RAM"; fi

# VM disks are sparse: they start small and grow up to VM_DISK_GIB each
LIMA_DIR="${LIMA_HOME:-$HOME/.lima}"; [[ -d "$LIMA_DIR" ]] || LIMA_DIR=$HOME
FREE_GIB=$(( $(df -Pk "$LIMA_DIR" | awk 'NR==2{print $4}') / 1024 ** 2 )) MAX_DISK=$((VMS * VM_DISK_GIB))
if (( FREE_GIB < 10 )); then fail "$FREE_GIB GiB free in $LIMA_DIR: images and packages alone need several GiB"
elif (( FREE_GIB < MAX_DISK )); then warn "$FREE_GIB GiB free in $LIMA_DIR: the VM disks can grow to $MAX_DISK GiB"
else ok "$FREE_GIB GiB free in $LIMA_DIR"; fi

echo "==> localhost:6443 (API server port forward)"
CP_STATUS=$(limactl list --format '{{.Status}}' "$CP" 2>/dev/null || true)
if ! nc -z -G 1 127.0.0.1 6443 2>/dev/null; then ok "free"
elif [[ "$CP_STATUS" == Running ]]; then ok "held by the running $CP VM (expected)"
else
  # lsof only sees this user's processes; a root-owned listener stays unnamed
  OWNER=$(lsof -nP -iTCP:6443 -sTCP:LISTEN 2>/dev/null | awk 'NR==2{print $1 " (pid " $2 ")"}' || true)
  fail "in use by ${OWNER:-another process}: up.sh's port forward needs it"
fi

if [[ -n "${EXTRA_CA:-}" ]]; then
  echo "==> Extra CA"
  if openssl x509 -noout -in "$EXTRA_CA" 2>/dev/null; then ok "$EXTRA_CA: $(openssl x509 -noout -subject -in "$EXTRA_CA")"
  else fail "$EXTRA_CA: not a readable PEM certificate"; fi
fi

if (( FAILED )); then echo "==> Not ready: fix the FAIL lines above" >&2; exit 1; fi
echo "==> Ready: run cluster/up.sh"
