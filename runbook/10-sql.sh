#!/usr/bin/env bash
# SQL Server 2016 SP2 FCI: reboot both nodes first (pending reboot blocks setup), install on n1, AddNode on n2, open ports.
source "$(dirname "$0")/lib.sh"
if [ "${SKIP_REBOOT:-0}" != 1 ]; then
  say "reboot nodes one at a time (clears pending-reboot flags)"
  for v in $N2 $N1; do reboot_wait $(vm_ip $v) domain; sleep 45; done
fi
for i in $(seq 1 30); do dwr $IP_N1 'Get-ClusterNode | % State' 2>/dev/null | grep -c Up | grep -q 2 && break; sleep 10; done
say "n1: InstallFailoverCluster (long)"; MODE=FCI rt $IP_N1 "$HERE/ps/sql-install.ps1" 5400 | tee /tmp/.sql1.$$
grep -q 'SETUP_EXIT=0' /tmp/.sql1.$$ || { rm -f /tmp/.sql1.$$; die "n1 setup failed (C:\\Program Files\\Microsoft SQL Server\\130\\Setup Bootstrap\\Log on n1)"; }; rm -f /tmp/.sql1.$$
say "n2: copy the SQL resource DLLs from n1 (see ps/copy-sql-dlls.ps1)"; rt $IP_N2 "$HERE/ps/copy-sql-dlls.ps1" 300
say "n2: AddNode";  MODE=ADD rt $IP_N2 "$HERE/ps/sql-install.ps1" 3600 | tee /tmp/.sql2.$$
grep -q 'SETUP_EXIT=0' /tmp/.sql2.$$ || { rm -f /tmp/.sql2.$$; die "n2 AddNode failed"; }; rm -f /tmp/.sql2.$$
say "firewall (both nodes)"
for ip in $IP_N1 $IP_N2; do dwr $ip 'New-NetFirewallRule -DisplayName "SQL 1433" -Direction Inbound -Protocol TCP -LocalPort 1433 -Action Allow -ErrorAction SilentlyContinue | Out-Null; New-NetFirewallRule -DisplayName "SQL Browser 1434" -Direction Inbound -Protocol UDP -LocalPort 1434 -Action Allow -ErrorAction SilentlyContinue | Out-Null; "ports ok"'; done
say "connect from the DC"; rt $IP_DC "$HERE/ps/sql-check.ps1" 120
