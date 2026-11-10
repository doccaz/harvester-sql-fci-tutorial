# On n1: LIO LUNs online, writable, GPT. Needed before Test-Cluster ("No disks" otherwise).
$wipe = ('__WIPE__' -eq '1')
# SCSI-3 reservations outlive the VMs that took them: a rebuilt cluster cannot write until they are cleared
# (reads work, Clear-Disk/Initialize-Disk fail with "Failed"). Only done when wiping.
if ($wipe) { Get-Disk | ? FriendlyName -like 'LIO*' | % { Clear-ClusterDiskReservation -Disk $_.Number -Force -ErrorAction SilentlyContinue } }
foreach ($n in (Get-Disk | ? FriendlyName -like 'LIO*' | % Number)) {
  $d = Get-Disk -Number $n
  if ($wipe -and $d.PartitionStyle -ne 'RAW') {
    Set-Disk -Number $n -IsOffline $false -ErrorAction SilentlyContinue; Set-Disk -Number $n -IsReadOnly $false -ErrorAction SilentlyContinue
    Clear-Disk -Number $n -RemoveData -RemoveOEM -Confirm:$false
  }
  Set-Disk -Number $n -IsOffline $false -ErrorAction SilentlyContinue
  Set-Disk -Number $n -IsReadOnly $false -ErrorAction SilentlyContinue
  if ((Get-Disk -Number $n).PartitionStyle -eq 'RAW') { Initialize-Disk -Number $n -PartitionStyle GPT }   # re-read: the wipe changed it
}
Get-Disk | ? FriendlyName -like 'LIO*' | ft Number,FriendlyName,@{n='GB';e={$_.Size/1GB}},PartitionStyle,OperationalStatus -AutoSize | Out-String
$n = @(Get-Disk | ? FriendlyName -like 'LIO*').Count; "LUNS_VISIBLE=$n"
$drv = Get-CimInstance Win32_PnPSignedDriver | ? { $_.DeviceClass -eq 'SCSIADAPTER' } | % DeviceName
"SCSI_ADAPTERS=" + ($drv -join ';')
