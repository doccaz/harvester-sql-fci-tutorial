# Demo: SQL Server 2016 FCI on Harvester v1.9.0 with shared SCSI-3 PR disks

LAB ONLY. The passwords below are the throwaway defaults from `env.example`; change them if the lab is reachable from anywhere but your own network. The generic procedure is in `shared-pr-disks.md`.

## Lab inventory (namespace `labs`)

| VM | IP | Host | Role |
|---|---|---|---|
| sqllab-dc1 | 192.168.100.170 | node-a | Domain controller `sqllab.local`, witness share, probe client |
| sqllab-fci-n1 | 192.168.100.171 | node-a | Cluster node 1 |
| sqllab-fci-n2 | 192.168.100.172 | node-b | Cluster node 2 |
| (cluster `sqllab-wsfc`) | 192.168.100.173 | | Cluster name |
| (SQL instance `SQLFCI`) | 192.168.100.174 | | Clustered SQL Server, default instance, TCP 1433 |

Shared LUNs (RWX Block PVCs, `lun` + `reservation: true`): `fci-quorum`, `fci-sqldata` (E:), `fci-sqllog` (F:).

## Accounts (console login)

| Account | Password | Where |
|---|---|---|
| `SQLLAB\Administrator` | `Sqllab2026` | Domain admin. Use this on all three VMs |
| `Administrator` (local) | `Sqllab2026` | Local account on n1/n2 (only if not logged in as domain user) |
| `SQLLAB\sqlsvc` | `Sqllab2026` | SQL service account; nobody logs in with it |
| `SQLLAB\SQLAdmins` | n/a | Group with sysadmin on the instance |

Login on the console: choose "Other user" and type `SQLLAB\Administrator`.
DSRM password: `Sqllab2026` (only used for AD recovery mode).

## Demo flow (about 15 minutes)

### 1. Show how the disks are wired (Harvester side, 2 min)
```bash
kubectl -n labs get pvc fci-quorum fci-sqldata fci-sqllog        # RWX, Block
kubectl -n labs get vm sqllab-fci-n1 -o yaml | grep -B2 -A6 'lun:'  # shareable, errorPolicy: report, lun/scsi/reservation
pod=$(kubectl -n labs get pods -l vm.kubevirt.io/name=sqllab-fci-n1 -o name | tail -1)
kubectl -n labs exec $pod -c compute -- virsh --connect 'qemu+unix:///session?socket=/var/run/libvirt/virtqemud-sock' \
  dumpxml labs_sqllab-fci-n1 | grep -E "device='lun'|pr-helper"
```
Point out: boot disk is VirtIO; shared disks are `lun` on SCSI; the two VMs sit on different hosts; the UI
cannot set `lun` in v1.9.0, so this part is YAML.

### 2. Show the cluster (n1 console, 2 min)
Failover Cluster Manager > Roles: `SQL Server (MSSQLSERVER)`, owner node, disks Online, witness share.
Or PowerShell:
```powershell
Get-ClusterNode | ft Name,State
Get-ClusterGroup | ft Name,OwnerNode,State
Get-ClusterResource | ft Name,ResourceType,State
```

### 3. Show the SCSI-3 PR validation result (2 min, on n1)
Do NOT run `Test-Cluster -Include Storage` now: the disks belong to the SQL role, so every storage test reports
"Not Applicable". Open the saved passing report instead (taken before SQL was installed; step 08 also saves a copy in `runbook/reports/`):
```powershell
Start-Process msedge 'C:\Windows\Cluster\Reports\PR-validation-PASS.htm'
```
Show Storage: "Validate SCSI-3 Persistent Reservation" and "Validate Disk Failover" = Success. (The failure with the public VMDP driver is described in shared-pr-disks.md.) A live re-run needs the SQL role offline and the
disks back in Available Storage: avoid it in a demo.

### 4. Start a client probe (DC console, keep it visible)
`vm\probe.ps1` equivalent, minimal version:
```powershell
while($true){ $t=Get-Date -f HH:mm:ss.fff
  try{ $c=New-Object Data.SqlClient.SqlConnection 'Server=SQLFCI;Integrated Security=SSPI;Connect Timeout=2'
       $c.Open(); $q=$c.CreateCommand(); $q.CommandText='select @@servername+'' on ''+cast(serverproperty(''ComputerNamePhysicalNetBIOS'') as varchar)'
       "$t OK   $($q.ExecuteScalar())"; $c.Close() } catch { "$t FAIL" }
  Start-Sleep -Milliseconds 400 }
```

### 5. Planned failover (~15-50 s outage)
On n1 or n2:
```powershell
Move-ClusterGroup -Name 'SQL Server (MSSQLSERVER)'
```
Watch the probe go FAIL for 15 to 50 s, then OK from the other node.

### 6. Hard failure (~35-50 s outage)
Pick one:
- Harvester UI: the owner VM > Force Stop. The role moves to the other node. The stopped VM may NOT
  restart by itself (harvester#11835); Start it manually.
- Or kill QEMU on the host (`kill -9` of the `qemu-system` process of that VM's virt-launcher). The VM restarts automatically.
The surviving node takes the reservation over (fencing), SQL comes up there.

### 7. Show data survived
```powershell
sqlcmd -S SQLFCI -E -Q "select name from sys.databases"
```
(If `sqlcmd` is missing, use the probe snippet with a different query.) Clean-up: the `fcitest` database from testing can be dropped.

## How the SCSI-3 PR validation was run (if someone asks)

Done once, BEFORE installing SQL (afterwards the disks belong to the SQL role and the tests say "Not Applicable").

Preconditions:
- Both nodes domain-joined and clustered (`sqllab-wsfc`); shared disks attached as `lun` + `reservation: true`.
- The three LUNs online and GPT-initialised on one node (otherwise `Test-Cluster` finds "No disks").
- Upstream virtio-win `vioscsi` driver on both nodes (the VMDP `pvvxscsi` driver fails the PR test).
- Lab only: `/etc/target/pr` present on the LIO node, otherwise every REGISTER errors and the test fails.

Command (elevated PowerShell on n1, domain admin; about 5 minutes; report goes to `C:\Windows\Cluster\Reports\`):
```powershell
Test-Cluster -Node sqllab-fci-n1,sqllab-fci-n2 -Include Storage -ReportName C:\Windows\Cluster\Reports\PR-validation-<date>
```
The PR test registers and reserves a disk from one node and checks that the other node is refused with a
RESERVATION CONFLICT, which proves the reservations reach the storage. Result: all Storage tests green
(`PR-validation-<date>.htm`, copied to `PR-validation-PASS.htm`; also saved in `runbook/reports/`).

## Talking points / limits
- VMs with PR disks cannot be live-migrated: node maintenance = guest failover, then stop the VM.
- A Harvester upgrade reverts the feature gate and pr-helper override: run `harvester-pr disable --apply` before, re-apply after.
- Needs a SAN with SCSI-3 PR (Longhorn/Ceph/NFS cannot back these). Here a Linux LIO target on Longhorn stands in
  (lab-only: it needs `/etc/target/pr` on its node, applied via CloudInit CR `pr-lab-lio-aptpl-dir`).
- Windows needs the upstream virtio-win `vioscsi` driver for the shared LUNs; the public VMDP `pvvxscsi` fails the PR test.
- Not tested: multipath in the data path, a real SAN, more than two nodes.

## Resetting the lab between demos
Move the role back to n1 (`Move-ClusterGroup -Name 'SQL Server (MSSQLSERVER)' -Node sqllab-fci-n1`), make sure both
VMs are running, and check `Get-ClusterNode` shows both Up.
