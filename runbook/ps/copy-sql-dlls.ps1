# Run on n2 before AddNode. SQL setup reads the cluster's resource types through WMI. The SQL types are already registered by n1's
# install, but n2 has no SQL resource DLLs in System32 yet, so n2's WMI list stops at the first SQL type and setup fails with
# "error to lookup cluster resource types ... Status code: 4098 ... Not found" (0x86D80018). Copying the DLLs from n1 first avoids it.
$ErrorActionPreference = 'Stop'
foreach ($f in 'sqsrvres.dll','sqagtres.dll','hadrres.dll','fssres.dll') { Copy-Item "\\sqllab-fci-n1\c$\Windows\System32\$f" C:\Windows\System32\ -Force }
"resource types visible to WMI on this node: " + @(Get-WmiObject -Namespace root\mscluster -Class MSCluster_ResourceType).Count
