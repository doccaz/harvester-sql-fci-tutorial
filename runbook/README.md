# Runbook: SQL Server 2016 FCI on Harvester v1.9.0 (native `lun` + SCSI-3 PR)

Numbered scripts that build the lab in the order that avoids every problem hit the first time. See the top-level `README.md` for the layout.
**Status: run end to end on 2026-11-10 (teardown + full rebuild); see "Test status".**

Needs `../env.local` (copy `../env.example`): kubeconfig, IPs, simple lab passwords.

| Step | Script | What / why |
|---|---|---|
| 00 | `00-prereqs.sh` | venv (pywinrm from PyPI), helm/virtctl/kubectl, feature gate, ISO checksums |
| 01 | `01-harvester-nodes.sh` | CloudInit CR creating `/etc/target/pr` on the LIO node (lab only; a real SAN does not need it). You run one `elemental cloud-init` command on the node. `WITH_MULTIPATH=1` adds the optional multipath CR |
| 02 | `02-luns.sh` | LIO target from `lio/chart` (helm) and PVs/PVCs for the three LUNs (1/4/2 GiB; sizes must stay distinct) |
| 03 | `03-iso-server.sh [up\|down]` | nginx pod on a node serves `iso/` (virtio-win, SQL) to the guests on :8099 |
| 04 | `04-golden-image.sh` | checks the golden image is complete (an empty image gave "No bootable devices" once) |
| 05 | `05-vms.sh` | dc1, n1, n2 from the image; Administrator password via guest agent (the cloud-config one is a race) |
| 06 | `06-dc.sh` | promote DC, second reboot (Netlogon), SQLAdmins, sqlsvc, witness share, DNS forwarder |
| 07 | `07-nodes-prep-join.sh` | IPv6 off, `vioscsi` replaces `pvvxscsi`, Failover-Clustering, reboot, domain join, reboot |
| 08 | `08-cluster.sh` | create cluster, LUNs online + GPT (`WIPE_LUNS=1` clears old data), **`Test-Cluster -Include Storage` before SQL**, saves `reports/PR-validation-PASS.htm` (stops if not PASS) |
| 09 | `09-cluster-disks.sh` | add LUNs to the cluster, name by size, format E: and F: (maintenance mode) |
| 10 | `10-sql.sh` | reboot nodes, `InstallFailoverCluster` on n1, `AddNode` on n2, firewall 1433/1434, connect test |
| 11 | `11-failover-tests.sh` | `planned`, `stop --yes`, `kill --yes`: probe from the DC, prints the outage |
| 90 | `90-verify.sh` | read-only status |
| 99 | `99-teardown.sh --yes` | deletes the 3 VMs and root disks only |

`run-all.sh` runs 00 to 10 then 90, pausing after 01.

## Differences from the first build (on purpose)
- Validation runs once, before SQL, under a dated name; the PASS copy is only made if PR and Disk Failover both succeed.
- vioscsi, Failover-Clustering and IPv6-off are applied per VM in step 07 instead of being baked into the golden image.
- The failover script checks both nodes Up and the role Online before and after each test, and uses `pkill` without a shell so it cannot kill itself.

## Test status (2026-11-10, full rebuild on the lab)
Four full builds were run from this tree. The last one was a complete run from scratch: a fresh `git clone` of the published repo, the golden image rebuilt by following `docs/golden-image.md` (about 24 min build + export), then steps 00 to 11 with no manual intervention: storage validation PASS (SCSI-3 PR and Disk Failover = Success), SQL FCI `SQLFCI` clustered on both nodes, and all three failover tests passed. Failover outage over the three builds: planned 16.2 / 51.0 / 21.0 / 32.2 / 16.8 s, Force Stop 37.8 / 33.0 / 41.6 / 37.8 s, `kill -9` 42.6 / 52.2 / 45.1 / 40.2 s (they vary from run to run). Rough step times in the last run: 05 VMs 19 min, 06 DC 9, 07 node prep + join 8, 08 cluster + validation 7, 10 SQL about 29, failover tests about 10.
The last build (after renaming the LIO release, namespace and CloudInit CR to `lio-san` and dropping two unused targets) ran steps 00 to 11 from a fresh clone with no failures and no manual intervention. None of the earlier builds ran clean on the first try; the fixes made along the way are listed below. The n2 AddNode fix (`ps/copy-sql-dlls.ps1`) was also validated on its own, starting from the failing state (n2's WMI shows 29 of 43 resource types).
Fixes made along the way (all in the scripts now):
- Windows Update must be off (step 05, `ps/no-windows-update.ps1`): a cumulative update that installs in the background while Failover-Clustering is being added makes the feature install fail or roll back ("We couldn't complete the features/updates. Undoing changes"), and it can take 30+ minutes before it does. Symptoms: `Install-WindowsFeature` error `0x80010108` or "could not update the provided feature files in the time allowed", a pending-reboot flag, WinRM silent while the console rolls back.
- AddNode on n2 needs the SQL resource DLLs in n2's System32 (step 10, `ps/copy-sql-dlls.ps1`). Without them n2's cluster WMI view is truncated and setup fails with `0x86D80018` (status 4098, "Not found"). A failed AddNode leaves n2 half-registered (later attempts then fail with "you must select at least one valid IP address for every subnet"): run `setup.exe /ACTION=RemoveNode /INSTANCENAME=MSSQLSERVER /CONFIRMIPDEPENDENCYCHANGE=1`, reboot n2, then AddNode again. Setup also refuses to start while a reboot is pending.
- ISO upload: `kubectl exec`/`cp` stdin cannot carry bulk data here; images go through Harvester's upload API (form field `chunk` for the `backingimage` backend). A standalone PVC with the `harvesterhci.io/imageId` annotation is EMPTY (the annotation only works in a VM's volumeClaimTemplates); use the image's own StorageClass. Served files are verified by SHA-256.
- Windows limits a command line to ~8 KB: `bg()` and `rt.py` upload scripts in chunks.
- Stale SCSI-3 reservations survive VM deletion: a rebuilt cluster cannot write to the LUNs (Clear-Disk "Failed", Test-Cluster "Not Applicable"). `WIPE_LUNS=1` runs `Clear-ClusterDiskReservation`, wipes and re-initialises the disks.
- `Start-Process -ArgumentList` does not quote: disk and IP arguments with spaces are quoted by hand; `/SECURITYMODE=Windows` is invalid (default).
- The `vioscsi` swap (remove `pvvxscsi` package, `pnputil /add-driver`) works; the script mounts the ISO before removing anything.
Still unverified: multipath in the data path, a real SAN, the golden-image rebuild from the Windows ISO (the existing image was reused), the optional `WITH_MULTIPATH=1`.
