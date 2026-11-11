# SQL Server 2016 Failover Cluster Instance on Harvester with native shared `lun` disks (SCSI-3 PR)

A hands-on lab tutorial: build a two-node Windows Server 2022 / SQL Server 2016 SP2 **Failover Cluster Instance** on **Harvester v1.9.0**, using KubeVirt `lun` disks with SCSI-3 Persistent Reservations as the shared storage, then run failover tests.

> **Lab/tutorial only.** Evaluation media, throwaway passwords (`Sqllab2026`, set in `env.example`), no hardening, Windows Update switched off. Do not use it as a production template.
> Português: veja [README.pt-BR.md](README.pt-BR.md).

## What you get

| Component | Detail |
|---|---|
| 3 Windows VMs | `sqllab-dc1` (domain controller + witness share), `sqllab-fci-n1`, `sqllab-fci-n2` (cluster nodes, on different Harvester hosts) |
| Shared storage | 3 RWX Block PVCs (quorum 1 GiB, data 4 GiB, log 2 GiB) attached as `lun` + `reservation: true`, served by a Linux LIO iSCSI target that stands in for a SAN |
| Result | Storage validation passes (SCSI-3 PR + Disk Failover) and the SQL FCI is up on both nodes. Measured failover outages over several full builds: planned 16-51 s, Force Stop 33-42 s, `kill -9` of QEMU 43-52 s. They vary from run to run, so plan a demo around one minute |

## Architecture

```
 your workstation                         Harvester v1.9.0 cluster (2+ nodes, Longhorn)
 ----------------                         -------------------------------------------------------------
 kubectl / helm / virtctl                 NODE_A                                  NODE_B
 runbook scripts  --- kubectl ------->      |  Linux LIO iSCSI target (pod)         |  ISO server (nginx pod, :8099)
      |                                     |  = the "SAN", exports 3 LUNs          |
      |                                     |        ^ iSCSI                        |
      |   WinRM (TCP 5985)                  |        |  (RWX Block PVCs, lun + SCSI-3 PR)
      +---------------------------------> sqllab-dc1   sqllab-fci-n1 <--------> sqllab-fci-n2
                                            AD DS, DNS,    node 1                  node 2
                                            witness share  \__ Windows failover cluster __/
                                                              SQL Server 2016 SP2 FCI "SQLFCI"
                                                              (disks: quorum 1G, SQLData E: 4G, SQLLog F: 2G)
```

The two cluster nodes run on different Harvester hosts. They see the same three LUNs as KubeVirt `lun` disks with `reservation: true`, so Windows Failover Clustering can use SCSI-3 persistent reservations to fence the node that lost the cluster.

## Requirements

**Harvester**
- v1.9.0 (the only version `harvester-pr` supports), with at least two schedulable nodes and the default Longhorn storage. The tests used a 3-node cluster with a witness node.
- A VM network on your LAN (a NetworkAttachmentDefinition, `LAN_NAD` in `env.example`) with 5 free static IPs in one subnet, and a gateway. The lab VMs need no internet (they fetch the ISOs from an in-cluster ISO server), but the golden image build does: its build VM downloads Cloudbase-Init from `cloudbase.it`, and the cluster pulls the VMDP driver image from `registry.suse.com`.
- Capacity for roughly: 30 GiB VM memory and 10 vCPUs (DC 6 GiB / 2, each node 12 GiB / 4), 3 x 60 GiB VM root disks, 36 GiB for the golden image (plus about 56 GiB temporarily while building it), 8 GiB for the ISO server volume, about 4.2 GiB of ISO images, and the 3 shared LUNs (7 GiB, kept by Longhorn with 2 replicas).

**Your workstation**
- `kubectl` with the Harvester kubeconfig, `helm`, `virtctl`, `python3` (with `venv`), `git`, `curl`, `ssh` access to the node that runs the LIO target.
- Network access to the VMs' IPs on TCP 5985 (WinRM). The runbook drives all guest configuration from here.

**Media** (not included): Windows Server 2022 evaluation ISO, SQL Server 2016 SP2 ISO, virtio-win ISO. See [iso/README.md](iso/README.md).

**Time**: about 25 minutes for the golden image (once), then roughly 1.5 hours for the runbook (VM clones 20 min, DC 9, node prep and join 8, cluster and validation 7, SQL 30, failover tests 10).

## Layout

| Path | What |
|---|---|
| `runbook/` | numbered scripts 00-99 (start with `runbook/README.md`) and `ps/` guest-side PowerShell |
| `docs/golden-image.md` | build the Windows golden image with the third-party [harvester-windows-cloudbase](https://github.com/abonillabeeche/harvester-windows-cloudbase) project (`golden/fetch-reference.sh` clones it) |
| `docs/shared-pr-disks.md` | the generic procedure for shared PR disks on Harvester (UI + YAML), requirements, limits |
| `docs/demo.md`, `docs/demo.pt-BR.md` | 15-minute demo script (EN / PT-BR) |
| `lio/` | LIO iSCSI target Helm chart, values, PVs/PVCs, CloudInit CRs |
| `vm/` | VM generator (`gen-vm.sh`) and WinRM runners |
| `harvester-pr` | enables/disables the KubeVirt PersistentReservation gate (Harvester v1.9.0 only) |
| `iso/` | where you put the installation media (see `iso/README.md`) |
| `scripts/verify-clean.sh` | pre-publish check for personal data and secrets (for people who fork this) |

## Quick start

1. Check the requirements above. Download the ISOs into `iso/` ([iso/README.md](iso/README.md)).
2. `cp env.example env.local` and set the kubeconfig path, node names (`kubectl get nodes`: `NODE_A` runs the DC, node 1 and the LIO target; `NODE_B` runs node 2 and the ISO server), the IPs and the network. The passwords are preset to a lab value; change them if you like.
3. Enable the PR feature gate: `./harvester-pr enable --apply` (see `docs/shared-pr-disks.md`). Note: a Harvester upgrade reverts it.
4. Build the golden image: [docs/golden-image.md](docs/golden-image.md).
5. Run the steps in `runbook/` in order, or `runbook/run-all.sh` for steps 00-10 and the verify step. **Step 01 needs one manual action:** the script creates a CloudInit CR and prints a command. Run it as root on the node that hosts the LIO target (`NODE_A`) over SSH, then continue:
   ```
   sudo elemental cloud-init -s boot /oem/96_lio_aptpl.yaml
   ls -ld /etc/target/pr        # must exist
   ```
   `run-all.sh` pauses there until you press Enter. This is only needed for the Linux LIO stand-in; a real SAN does not need it.
6. Measure failovers with `runbook/11-failover-tests.sh planned | stop --yes | kill --yes`, and show it with `docs/demo.md`.

If a step fails, `runbook/README.md` lists the problems hit while building this and their fixes (Windows Update, leftover SCSI-3 reservations, the SQL AddNode failure, and others).

## Cleaning up

| What | How |
|---|---|
| The 3 Windows VMs and their root disks | `runbook/99-teardown.sh --yes` (keeps the LUNs, golden image and node config) |
| ISO server pod, its volume and the two ISO images | `runbook/03-iso-server.sh down` |
| Shared LUNs and the LIO target (untested) | delete PVCs and PVs `fci-quorum`, `fci-sqldata`, `fci-sqllog`, then `helm uninstall lio-san` |
| Golden image | `kubectl -n labs delete virtualmachineimage win2022-cloudbase` |

Before rebuilding on the same LUNs set `WIPE_LUNS=1` in `env.local`: stale SCSI-3 reservations survive VM deletion and would block the new cluster.

## Good to know

- Windows Update is switched off on the VMs on purpose (step 05): a cumulative update that installs while Failover-Clustering is being added makes the install fail and roll back.
- Multipath in the data path and a real SAN were not tested. `./harvester-pr enable` was not re-run from this repository's final state.

## Credits and licence
MIT, see [LICENSE](LICENSE). The golden image approach builds on [harvester-windows-cloudbase](https://github.com/abonillabeeche/harvester-windows-cloudbase) (Apache-2.0, cloned separately). Windows, SQL Server and the virtio-win ISO are subject to their own licences and are not distributed here.
