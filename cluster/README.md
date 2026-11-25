# CKS lab cluster

2-node kubeadm cluster (`cks-cp` + `cks-worker`) on [Lima](https://lima-vm.io/) VMs: Ubuntu 24.04, containerd 2.x, Kubernetes v1.37 (exam version), Cilium CNI, AppArmor enabled.

```sh
brew install lima
cluster/up.sh                                   # create or resume; safe to re-run
EXTRA_CA=/path/corp-ca.pem cluster/up.sh        # behind a TLS-inspecting proxy

export KUBECONFIG=~/.kube/cks                   # from the Mac (API via localhost:6443)
limactl shell cks-cp                            # or work on the nodes, like in the exam
```

| Action | Command |
|---|---|
| Stop | `limactl stop cks-worker cks-cp` |
| Start | `limactl start cks-cp cks-worker` (node IPs are stable across restarts) |
| Destroy | `cluster/down.sh` (VMs + `~/.kube/cks`; safe to re-run) |
