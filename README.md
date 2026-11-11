# SQL Server 2016 Failover Cluster Instance on Harvester with native shared `lun` disks (SCSI-3 PR)

A hands-on lab tutorial: build a two-node Windows Server 2022 / SQL Server 2016 SP2 **Failover Cluster Instance** on **Harvester v1.9.0**, using KubeVirt `lun` disks with SCSI-3 Persistent Reservations as the shared storage, then run failover tests.

> **Lab/tutorial only.** Evaluation media, throwaway passwords (`Sqllab2026`, set in `env.example`), no hardening. Do not use it as a production template.
> Português: veja [README.pt-BR.md](README.pt-BR.md).

## What you get

| Component | Detail |
|---|---|
| 3 Windows VMs | `sqllab-dc1` (domain controller + witness share), `sqllab-fci-n1`, `sqllab-fci-n2` (cluster nodes, on different Harvester hosts) |
| Shared storage | 3 RWX Block PVCs (quorum 1 GiB, data 4 GiB, log 2 GiB) attached as `lun` + `reservation: true`, served by a Linux LIO iSCSI target that stands in for a SAN |
| Result | Storage validation passes (SCSI-3 PR + Disk Failover), SQL FCI up, measured failover outages over two full builds: planned 16-51 s, Force Stop 33-42 s, `kill -9` of QEMU 43-52 s over several full builds (they vary; plan demos around ~1 min) |

## Layout

| Path | What |
|---|---|
| `runbook/` | numbered scripts 00-99 (start with `runbook/README.md`) and `ps/` guest-side PowerShell |
| `docs/shared-pr-disks.md` | the generic procedure for shared PR disks on Harvester (UI + YAML), requirements, limits |
| `docs/demo.md`, `docs/demo.pt-BR.md` | 15-minute demo script (EN / PT-BR) |
| `lio/` | LIO iSCSI target Helm chart, values, PVs/PVCs, CloudInit CRs |
| `docs/golden-image.md`, `golden/` | how to build the Windows golden image with the third-party [harvester-windows-cloudbase](https://github.com/abonillabeeche/harvester-windows-cloudbase) project (`golden/fetch-reference.sh` clones it) |
| `vm/` | VM generator (`gen-vm.sh`) and WinRM runners |
| `harvester-pr` | enables/disables the KubeVirt PersistentReservation gate (Harvester v1.9.0 only) |
| `iso/` | where you put the installation media (not included, see `iso/README.md`) |

## Quick start

1. A Harvester v1.9.0 cluster with two schedulable nodes, Longhorn, and a VM network reachable from your workstation.
2. Download the ISOs into `iso/` ([iso/README.md](iso/README.md)). Install `kubectl`, `helm`, `virtctl`, `python3`.
3. `cp env.example env.local` and set the kubeconfig path, node names (`kubectl get nodes`), IPs, and network. Passwords are preset to a lab value; change them if you like.
4. Enable the PR feature gate: `./harvester-pr enable --apply` (see `docs/shared-pr-disks.md`).
5. Build the golden image ([docs/golden-image.md](docs/golden-image.md)), then run `runbook/run-all.sh` or the numbered steps one by one.
6. Follow `docs/demo.md` to show it, and `runbook/11-failover-tests.sh` to measure failovers.

## Known gaps
Multipath in the data path, a real SAN, and a from-scratch golden image rebuild following `docs/golden-image.md` were not verified. See `runbook/README.md` ("Fixes made along the way") for the problems hit and their solutions.

## Credits and licence
MIT, see [LICENSE](LICENSE). The golden image approach builds on [harvester-windows-cloudbase](https://github.com/abonillabeeche/harvester-windows-cloudbase) (Apache-2.0, cloned separately). Windows, SQL Server and the virtio-win ISO are subject to their own licences and are not distributed here.
