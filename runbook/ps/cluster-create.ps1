# On n1 as domain admin (rt.py). No storage yet: disks are added after validation.
Import-Module FailoverClusters
if (-not (Get-Cluster -ErrorAction SilentlyContinue)) {
  New-Cluster -Name sqllab-wsfc -Node sqllab-fci-n1,sqllab-fci-n2 -StaticAddress __IP_CLUSTER__ -NoStorage | Out-Null
}
Set-ClusterQuorum -FileShareWitness \\sqllab-dc1\fciwitness | Out-Null
Get-ClusterNode | ft Name,State -AutoSize | Out-String
Get-ClusterQuorum | ft QuorumType,QuorumResource -AutoSize | Out-String
