# Per cluster node, before the domain join. Detached as SYSTEM. Ends with a reboot.
$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue'
Start-Transcript C:\prepnode.log -Force
try {
  # IPv6 off: the router's IPv6 RDNSS returns NXDOMAIN for the AD domain
  Get-NetAdapter | % { Disable-NetAdapterBinding -Name $_.Name -ComponentID ms_tcpip6 -ErrorAction SilentlyContinue }

  # upstream virtio-win vioscsi in place of the public VMDP pvvxscsi (which fails the SCSI-3 PR test)
  $want = '__VIRTIO_SHA__'
  if (-not (Test-Path C:\virtio-win.iso) -or (Get-FileHash C:\virtio-win.iso -Algorithm SHA256).Hash -ine $want) {
    Remove-Item C:\virtio-win.iso -Force -ErrorAction SilentlyContinue
    Invoke-WebRequest -UseBasicParsing -Uri '__VIRTIO_URL__' -OutFile C:\virtio-win.iso
  }
  if ((Get-FileHash C:\virtio-win.iso -Algorithm SHA256).Hash -ine $want) { throw 'virtio-win.iso checksum mismatch (bad copy on the ISO server?)' }
  # mount and check the driver is there BEFORE touching the installed driver
  $dl = (Mount-DiskImage C:\virtio-win.iso -PassThru | Get-Volume).DriveLetter
  $inf = "${dl}:\vioscsi\2k22\amd64\vioscsi.inf"
  if (-not (Test-Path $inf)) { throw "vioscsi.inf not found at $inf" }
  $txt = pnputil /enum-drivers | Out-String
  foreach ($blk in ($txt -split "(?:\r?\n){2,}")) {
    if ($blk -match 'Original Name:\s+pvvxscsi\.inf' -and $blk -match 'Published Name:\s+(oem\d+\.inf)') { pnputil /delete-driver $Matches[1] /uninstall /force }
  }
  pnputil /add-driver $inf /install
  pnputil /scan-devices
  Dismount-DiskImage C:\virtio-win.iso | Out-Null
  Remove-Item C:\virtio-win.iso -Force

  # Failover Clustering here so the pending reboot is consumed before SQL setup
  # Right after the driver swap DISM can answer 0x80010108 (RPC disconnected) for a while: retry
  for ($i = 1; $i -le 6; $i++) {
    try { Install-WindowsFeature Failover-Clustering -IncludeManagementTools -ErrorAction Stop | Out-Null; break }
    catch { if ($i -eq 6) { throw }; "Install-WindowsFeature attempt $i failed: $($_.Exception.Message.Split([char]10)[0]); retrying in 30 s"; Start-Sleep 30 }
  }
  Set-Content C:\prepnode.done ok
  Stop-Transcript
  Restart-Computer -Force
} catch { $_ | Out-String; Set-Content C:\prepnode.fail ($_ | Out-String); Stop-Transcript }
