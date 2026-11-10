# Lab only: stop Windows Update from servicing in the background. A cumulative update that lands while the
# Failover-Clustering feature or SQL setup is being installed makes both fail ("We couldn't complete the updates/features, undoing changes").
$ErrorActionPreference = 'SilentlyContinue'
$p = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
New-Item "$p\AU" -Force | Out-Null
Set-ItemProperty "$p\AU" NoAutoUpdate 1 -Type DWord
Set-ItemProperty "$p\AU" AUOptions 1 -Type DWord
foreach ($s in 'wuauserv','UsoSvc') { Stop-Service $s -Force; Set-Service $s -StartupType Disabled }
Get-ScheduledTask -TaskPath '\Microsoft\Windows\UpdateOrchestrator\*','\Microsoft\Windows\WindowsUpdate\*' | Disable-ScheduledTask | Out-Null
'windows update disabled: ' + (Get-Service wuauserv).StartType
