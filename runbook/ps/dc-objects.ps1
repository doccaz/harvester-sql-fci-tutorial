# Domain controller, after the second boot: DNS client/forwarder, SQLAdmins, sqlsvc, witness share. Idempotent.
$ErrorActionPreference = 'Stop'
Import-Module ActiveDirectory
$nic = (Get-NetAdapter | ? Status -eq Up | select -First 1).Name
Set-DnsClientServerAddress -InterfaceAlias $nic -ServerAddresses 127.0.0.1
if (-not (Get-DnsServerForwarder).IPAddress) { Add-DnsServerForwarder -IPAddress __GATEWAY__ }   # nodes use this DC for internet names too
if (-not (Get-ADGroup -Filter "Name -eq 'SQLAdmins'")) { New-ADGroup -Name SQLAdmins -GroupScope Global }
if (-not (Get-ADUser -Filter "Name -eq 'sqlsvc'")) {
  New-ADUser -Name sqlsvc -SamAccountName sqlsvc -AccountPassword (ConvertTo-SecureString '{{SQLSVC_PASSWORD}}' -AsPlainText -Force) -Enabled $true -PasswordNeverExpires $true
}
Add-ADGroupMember -Identity SQLAdmins -Members Administrator -ErrorAction SilentlyContinue
New-Item C:\fciwitness -ItemType Directory -Force | Out-Null
if (-not (Get-SmbShare -Name fciwitness -ErrorAction SilentlyContinue)) { New-SmbShare -Name fciwitness -Path C:\fciwitness -FullAccess 'Everyone' | Out-Null }  # lab: the cluster account needs write
'DC objects ready: ' + ((Get-ADGroup SQLAdmins).Name) + ', ' + ((Get-ADUser sqlsvc).Name) + ', share fciwitness'
