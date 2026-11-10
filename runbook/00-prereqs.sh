#!/usr/bin/env bash
# Local tooling + cluster feature gate. Safe to re-run.
source "$(dirname "$0")/lib.sh"
command -v kubectl >/dev/null || die "kubectl missing"; command -v python3 >/dev/null || die "python3 missing"
[ -x "$PY" ] || { say "creating venv (pywinrm from PyPI)"; python3 -m venv "$HERE/.venv"; "$HERE/.venv/bin/pip" -q install pywinrm pyyaml; }
command -v helm >/dev/null || die "helm missing (needed to deploy the LIO target in step 02)"
command -v virtctl >/dev/null || die "virtctl missing: install it from https://github.com/kubevirt/kubevirt/releases (match your Harvester's KubeVirt version) and put it in PATH or tools/bin"
"$PY" -c 'import winrm' || die "pywinrm missing in venv"
kubectl get nodes >/dev/null || die "cannot reach the cluster (KUBECONFIG in env.local)"
say "Harvester/KubeVirt"
kubectl -n harvester-system get kubevirt kubevirt -o jsonpath='{.spec.configuration.developerConfiguration.featureGates}{"\n"}' | grep -q PersistentReservation || die "PersistentReservation gate is not enabled: run the harvester-pr tool / docs/shared-pr-disks.md section 2 first"
kubectl -n harvester-system get pods -l kubevirt.io=virt-handler --no-headers
for f in virtio-win-0.1.302.iso sql2016-sp2-x64-en.iso; do [ -f "$ROOT/iso/$f" ] || die "missing iso/$f"; done
(cd "$ROOT/iso" && sha256sum -c SHA256SUMS >/dev/null 2>&1) && echo "iso checksums ok" || echo "WARN: iso/SHA256SUMS missing or mismatching"
echo "prereqs ok"
