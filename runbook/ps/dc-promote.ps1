# Domain controller: AD DS + DNS, new forest. Detached as SYSTEM; the forest install reboots the VM.
$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue'
Start-Transcript C:\dcpromote.log -Force
try {
  Install-WindowsFeature AD-Domain-Services, DNS -IncludeManagementTools | Out-Null
  $sp = ConvertTo-SecureString '{{DSRM_PASSWORD}}' -AsPlainText -Force
  Set-Content C:\dcpromote.done ok
  Install-ADDSForest -DomainName __DOMAIN__ -DomainNetbiosName __NETBIOS__ -SafeModeAdministratorPassword $sp -InstallDns -Force
} catch { Set-Content C:\dcpromote.fail ($_ | Out-String); Remove-Item C:\dcpromote.done -ErrorAction SilentlyContinue }
