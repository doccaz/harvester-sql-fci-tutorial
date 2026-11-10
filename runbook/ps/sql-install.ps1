# Run as domain admin on the node (rt.py). __MODE__ = FCI (first node, owns the disks) or ADD (second node).
$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue'
Start-Transcript C:\sqlsetup.log -Force | Out-Null
if (-not (Test-Path C:\sql2016.iso) -or (Get-Item C:\sql2016.iso).Length -lt 1GB) {
  Invoke-WebRequest -UseBasicParsing -Uri '__SQL_URL__' -OutFile C:\sql2016.iso
}
if ((Get-Item C:\sql2016.iso).Length -lt 1GB) { throw 'SQL ISO download failed or is not a real ISO' }
$dl = (Mount-DiskImage C:\sql2016.iso -PassThru | Get-Volume).DriveLetter
$common = @('/IACCEPTSQLSERVERLICENSETERMS', '/QUIET', '/INDICATEPROGRESS=False', '/UPDATEENABLED=False', '/INSTANCENAME=MSSQLSERVER',
  '/SQLSVCACCOUNT=__NETBIOS__\sqlsvc', '/SQLSVCPASSWORD={{SQLSVC_PASSWORD}}',
  '/AGTSVCACCOUNT=__NETBIOS__\sqlsvc', '/AGTSVCPASSWORD={{SQLSVC_PASSWORD}}',
  '/FAILOVERCLUSTERIPADDRESSES="IPv4;__IP_FCI__;Cluster Network 1;255.255.255.0"')   # Start-Process does not quote: embed the quotes
if ('__MODE__' -eq 'FCI') {
  $args2 = @('/ACTION=InstallFailoverCluster', '/FEATURES=SQLENGINE', '/FAILOVERCLUSTERGROUP="SQL Server (MSSQLSERVER)"',
    '/FAILOVERCLUSTERDISKS="Cluster Disk - SQLData"', '"Cluster Disk - SQLLog"',       # each disk is its own quoted argument
    '/FAILOVERCLUSTERNETWORKNAME=SQLFCI', '/INSTALLSQLDATADIR=E:\', '/SQLUSERDBLOGDIR=F:\MSSQL\Log',
    '/SQLSYSADMINACCOUNTS=__NETBIOS__\SQLAdmins')   # Windows auth is the default; /SECURITYMODE accepts only SQL
} else {
  $args2 = @('/ACTION=AddNode')
}
$p = Start-Process -FilePath "${dl}:\setup.exe" -ArgumentList ($common + $args2) -Wait -PassThru
Dismount-DiskImage C:\sql2016.iso | Out-Null
Stop-Transcript | Out-Null
"SETUP_EXIT=$($p.ExitCode)"
if ($p.ExitCode -ne 0 -and $p.ExitCode -ne 3010) { Get-ChildItem 'C:\Program Files\Microsoft SQL Server\130\Setup Bootstrap\Log\Summary.txt' -ErrorAction SilentlyContinue | Get-Content -Tail 40 }
