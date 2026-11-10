# Shared SCSI-3 persistent-reservation disks on Harvester v1.9.0 (UI + YAML)

**Scope: Harvester v1.9.0 only.**

How to give two or more Windows (or Linux) cluster VMs a **shared LUN with SCSI-3
persistent reservations (PR)**, as needed by a Windows Failover Cluster / SQL Server FCI.

On Harvester v1.9.0 the VM form in the UI cannot set this up completely. The disk
**Type** list only offers `disk` and `cd-rom` (no `lun`) and there is no PR checkbox.
So the procedure is: create the VM in the UI, then change the shared disks to `lun`
in the VM's YAML.

> Status: the steps below were tested in a lab on Harvester v1.9.0 with Linux guests
> and an iSCSI target (see "What was tested"). Items marked **(not verified)** are
> taken from upstream material or were not exercised. Always validate on your own
> storage before relying on it.

## 1. Requirements

**Storage**
- A SAN that supports SCSI-3 PR, reached over iSCSI (or FC) through a CSI driver or
  static PVs. Longhorn, Ceph RBD and NFS cannot back these disks.
- Each shared disk is a PVC with `accessModes: [ReadWriteMany]` and
  `volumeMode: Block`.

**Hosts (every node that can run a cluster VM)**
- Each node has a **unique** iSCSI initiator name. Check
  `/etc/iscsi/initiatorname.iscsi` on every node. Clusters installed before v1.5 may
  share one name, which makes fencing meaningless.
- If you use multipath: scope settings to the SAN vendor's devices with
  `reservation_key file` and `skip_kpartx yes`, and make sure `/etc/multipath` is mode
  `0755` (with `0644`, `qemu-pr-helper` cannot read its key file and reservations
  silently never reach the array). **(not verified; the lab ran single-path)**

**Placement**
- Pin each cluster VM to a **different** host (node selector or anti-affinity).
  Reservations belong to the host's initiator, so two VMs on one host cannot fence
  each other.

**Guest (Windows)**
- Windows Server 2022, boot disk on **VirtIO**. Do not put the boot disk on the SCSI
  bus, otherwise Windows treats shared LUNs as "on the system bus" and sends no PR
  commands. **(upstream, not verified)**
- The public SUSE VMDP `pvvxscsi` driver (1.0.1.14) rejects shared LUNs and mishandles
  RESERVATION CONFLICT. Use the upstream virtio-win `vioscsi` driver for the shared
  LUNs, or ask SUSE support for the fixed VMDP build. Workaround from upstream:
  set `BusType` (DWORD) = `0xA` under
  `HKLM\SYSTEM\CurrentControlSet\Services\pvvxscsi\Parameters` and reboot.
  **(upstream, not verified)**

## 2. Enable persistent reservation (cluster admin, once)

The Harvester setting `persistent-reservation-enabled` does not exist in v1.9.0, so
enable the KubeVirt feature gate. Check the current state first:

```bash
kubectl -n harvester-system get kubevirt kubevirt \
  -o jsonpath='{.spec.configuration.developerConfiguration.featureGates}{"\n"}'
kubectl -n harvester-system get pods -l kubevirt.io=virt-handler
```

On v1.9.0 the default pr-helper image tag derived by KubeVirt does not exist in the
registry, so enabling the gate alone would crash-loop `virt-handler`. In the lab this
was fixed by overriding the image **before** enabling the gate:

```bash
# 1. image override (verify the tag exists first, e.g. with skopeo inspect)
kubectl -n harvester-system set env deploy/virt-operator \
  PR_HELPER_IMAGE=registry.suse.com/suse/sles/16.0/pr-helper:1.8.4-11.9
kubectl -n harvester-system rollout status deploy/virt-operator

# 2. enable the gate
kubectl -n harvester-system patch kubevirt kubevirt --type=json -p \
  '[{"op":"add","path":"/spec/configuration/developerConfiguration/featureGates/-","value":"PersistentReservation"}]'

# 3. watch: virt-handler must end up 2/2 Running with 0 restarts
kubectl -n harvester-system get pods -l kubevirt.io=virt-handler -w
```

If `virt-handler` crash-loops, remove the gate immediately (this disrupts VM management
on every node until fixed).

Notes:
- This guide covers **Harvester v1.9.0 only** (KubeVirt 1.8.4-9.1). Do not apply it to
  other releases without checking; the image tag, the enabling switch and the UI differ
  between versions. The upstream article lists a fixed pr-helper for v1.9.0, but in our
  lab the default image tag still did not exist in the registry, so check it first.
- **A Harvester upgrade reverts the gate and the image override.** VMs with PR disks
  then fail to start. Remove the gate before upgrading and re-apply it afterwards.
- VMs with PR disks **cannot be live-migrated**. Plan node maintenance as a guest-cluster
  failover followed by a VM shutdown.

## 3. Create the shared volumes

Create one PVC per shared disk (for example a witness, a data disk and a log disk),
`ReadWriteMany` + `volumeMode: Block`, from the SAN's StorageClass. Create them once;
all cluster VMs reference the same PVCs.

## 4. Create each VM in the UI

1. **Virtual Machines → Create.** Set name, namespace, CPU and memory.
2. **Volumes:** keep the boot disk on **VirtIO** (image volume or your Windows image).
3. **Volumes → Add Existing Volume:** add each shared PVC. The shared PVCs appear in
   the list. Leave Type as `disk` for now.
4. **Node Scheduling:** pin this VM to its own host. **(not exercised in the lab UI)**
5. Add networks, cloud-init and so on as usual, then **Create**.

If the new VM is created Running, **stop it** before the next step. With the shared
volumes as plain disks it may fail to start; that is expected.

## 5. Change the shared disks to `lun` (YAML)

Open the VM, **⋮ → Edit YAML** (or `kubectl -n <ns> edit vm <name>`). Under
`spec.template.spec.domain.devices.disks`, find the entries for the shared volumes. The
UI wrote them like this:

```yaml
- name: disk-1
  bootOrder: 2
  disk:
    bus: virtio
```

Replace **each shared disk entry entirely** with:

```yaml
- name: disk-1               # keep the same names as in the volumes list
  shareable: true
  errorPolicy: report
  lun:
    bus: scsi
    reservation: true
```

- Remove `disk:` and `bootOrder:`. A disk cannot be both `disk` and `lun`.
- `shareable: true` lets several VMs use the same volume.
- `errorPolicy: report` passes the expected RESERVATION CONFLICT to the guest. With the
  default `stop`, the VM would be paused when a fenced node hits it.
- Leave `spec.template.spec.volumes` unchanged (each shared PVC stays a
  `persistentVolumeClaim` volume).
- Repeat on every cluster VM (same PVCs, same entries).

Save, then **Start** the VM. Harvester's webhook accepted this change on an existing
VM in the lab.

## 6. Verify

**Is PR wired into QEMU?** (cluster admin)

```bash
pod=$(kubectl -n <ns> get pods -l vm.kubevirt.io/name=<vm> -o name | tail -1)
kubectl -n <ns> exec $pod -c compute -- \
  virsh --connect 'qemu+unix:///session?socket=/var/run/libvirt/virtqemud-sock' \
  dumpxml <ns>_<vm> | grep -E "device='lun'|reservations|pr-helper"
```

Each shared disk should show `device='lun'` and a `<reservations ...>` block with
`.../pr/pr-helper.sock`.

**Do reservations actually conflict?** (Linux test VMs, `sg3_utils`)

On VM A: `sg_persist --out --register-ignore --param-sark=0xa1 /dev/sdX` then
`sg_persist --out --reserve --param-rk=0xa1 --prout-type=5 /dev/sdX`.
On VM B: register `0xb2`, then try the same reserve with `0xb2`. It **must fail with
exit code 24 (RESERVATION CONFLICT)**. If it succeeds, the reservation is not reaching
the array.

Note: in the lab, REGISTER commands printed "Device not ready" (exit 2) but still
took effect (keys appeared in `--read-keys`). Judge by the key list, not that message.

**Windows:** install Failover Clustering, form the cluster, then run

```powershell
Test-Cluster -Node <n1>,<n2> -Include "Storage"
```

All storage tests, including **Validate SCSI-3 Persistent Reservation**, must pass
before installing SQL Server (`/ACTION=InstallFailoverCluster`). **(Passed in the lab with `vioscsi`; see "What was tested".)**

## 7. Known limits and gotchas

- No `lun` option or PR checkbox in the UI on v1.9.0; the upstream UI work (and a
  `persistent-reservation-enabled` setting, harvester#12059) is still in review.
- No live migration for VMs with PR disks.
- A VM with `runStrategy: RerunOnFailure` may refuse to start after
  `virtctl stop --force` (harvester#11835, open upstream). **(upstream)**
- Open SQL ports by hand on every node after setup: TCP 1433, UDP 1434 (SQL Browser).
- Connect to the cluster instance by name, not IP.
- Typical failover times seen upstream: about 10 s (Force Stop), about 27 s (hard kill of
  the owner). Do not shorten the cluster heartbeat settings to speed this up.

## What was tested (lab, 2026-11-09)

- Harvester v1.9.0, KubeVirt 1.8.4, two worker nodes, Longhorn-only cluster using a
  Linux LIO iSCSI target as a stand-in for a SAN. Host multipath off (single path).
- Two Linux VMs (one per host) with two shared `lun` disks: the full register / reserve /
  conflict (exit 24) / fence / clear sequence behaved correctly, and the fenced VM kept
  running.
- A VM created in the UI with the shared volumes as plain disks, then edited to `lun` +
  `reservation: true` via `kubectl patch`, started and showed `device='lun'` with
  `pr-helper.sock` reservations in libvirt. The UI's own YAML editor was **not** used.
- Windows Server 2022 guests (2 nodes + DC, boot disk on VirtIO, three shared `lun` disks with
  reservations): `Test-Cluster -Include Storage` passed **only with the upstream virtio-win
  `vioscsi` driver** (all tests incl. SCSI-3 Persistent Reservation, Disk Failover). With the
  public SUSE VMDP `pvvxscsi` driver (even with the `BusType=0xA` workaround) the PR test failed:
  a second node could RESERVE a disk held by the first.
- SQL Server 2016 SP2 FCI installed on that cluster; measured client downtime (probe from a third VM):
  planned move ~20 s, Force Stop of the owner VM ~37 s, `kill -9` of QEMU ~40 s; data persisted across
  moves. A Force-Stopped VM did not restart by itself under `RerunOnFailure` (harvester#11835).
- Lab-only trap: a Linux LIO target stand-in for the SAN needs `/etc/target/pr` to exist on the node
  running it, otherwise every REGISTER takes effect but returns "LOGICAL UNIT COMMUNICATION FAILURE",
  which makes Windows validation fail. Real arrays are unaffected.
- Rebuild on the same LUNs (2026-11-10, full teardown and rebuild with scripts): storage validation passed again; client outage planned move 16 s, Force Stop 38 s, `kill -9` of QEMU 43 s.
- Trap when rebuilding a cluster on the same LUNs: SCSI-3 reservations survive deleting the VMs. The new cluster can read but not write (Clear-Disk fails, `Test-Cluster` reports every storage test "Not Applicable"). Clear them first with `Clear-ClusterDiskReservation -Disk <n> -Force` on a node, then wipe and re-initialise the disks (GPT).
- Run `Test-Cluster -Include Storage` BEFORE the disks join the cluster and before SQL setup; afterwards it only reports "Not Applicable" (disks in use).
- Not tested: multipath in the data path, a real SAN, more than two nodes.

Upstream reference: https://blog.5glinux.com/posts/wsfc-sql-fci-shared-san-luns-suse-virtualization/
