# On n1 as domain admin: add the LUNs to the cluster, name them by size, format the two SQL disks.
# Sizes come from the PVCs: quorum 1 GiB, SQLData 4 GiB (E:), SQLLog 2 GiB (F:). Sizes must be distinct.
Import-Module FailoverClusters
Get-ClusterAvailableDisk | Add-ClusterDisk | Out-Null
$map = @{ 1 = @{n='Cluster Disk - Quorum'}; 4 = @{n='Cluster Disk - SQLData'; l='E'; v='SQLData'}; 2 = @{n='Cluster Disk - SQLLog'; l='F'; v='SQLLog'} }
foreach ($res in (Get-ClusterResource | ? ResourceType -eq 'Physical Disk')) {
  $id = (Get-ClusterParameter -InputObject $res -Name DiskIdGuid).Value
  $d = Get-Disk | ? { $_.Guid -eq $id -or $_.Guid -eq "{$id}" -or "{$($_.Guid)}" -eq $id }
  if (-not $d) { "no local disk for $($res.Name) (owned by the other node?)"; continue }
  $gb = [int][math]::Round($d.Size / 1GB); $m = $map[$gb]
  if (-not $m) { "unexpected size $gb GB for $($res.Name)"; continue }
  if ($m.l) {
    Suspend-ClusterResource -Name $res.Name | Out-Null           # maintenance mode, else format fails
    Set-Disk -Number $d.Number -IsOffline $false -ErrorAction SilentlyContinue
    if (-not (Get-Partition -DiskNumber $d.Number -ErrorAction SilentlyContinue | ? DriveLetter)) {
      New-Partition -DiskNumber $d.Number -UseMaximumSize -DriveLetter $m.l | Format-Volume -FileSystem NTFS -NewFileSystemLabel $m.v -AllocationUnitSize 65536 -Confirm:$false | Out-Null
    }
    Resume-ClusterResource -Name $res.Name | Out-Null
  }
  $res.Name = $m.n
}
Get-ClusterResource | ft Name,ResourceType,State,OwnerGroup -AutoSize | Out-String
