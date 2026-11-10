# On n1 as domain admin. The one validation that matters: BEFORE the disks join the cluster / SQL is installed.
Import-Module FailoverClusters
$name = 'C:\Windows\Cluster\Reports\PR-validation-' + (Get-Date -Format 'yyyyMMdd-HHmm')
$r = Test-Cluster -Node sqllab-fci-n1,sqllab-fci-n2 -Include Storage -ReportName $name
$f = "$name.htm"; if (-not (Test-Path $f)) { $f = $r.FullName }
$t = Get-Content $f -Raw
function res($n) { [regex]::Match($t, [regex]::Escape($n) + '.{0,400}?(Success|Failed|Not Applicable|Warning)', 'Singleline').Groups[1].Value }
$pr = res 'Validate SCSI-3 Persistent Reservation'; $fo = res 'Validate Disk Failover'
"REPORT=$f"; "PR=$pr"; "FAILOVER=$fo"
if ($pr -eq 'Success' -and $fo -eq 'Success') { Copy-Item $f 'C:\Windows\Cluster\Reports\PR-validation-PASS.htm' -Force; 'RESULT=PASS' } else { 'RESULT=FAIL' }
