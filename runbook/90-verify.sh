#!/usr/bin/env bash
# Read-only status of the whole lab.
source "$(dirname "$0")/lib.sh"
kubectl -n "$NS" get vmi 2>/dev/null | grep -E 'NAME|sqllab'
for ip in $IP_DC $IP_N1 $IP_N2; do printf '%s: ' $ip; dwr $ip 'hostname' 2>&1 | tr -d '\r' | head -1; done
dwr $IP_N1 'Get-ClusterNode | ft Name,State -AutoSize | Out-String; Get-ClusterGroup | ft Name,OwnerNode,State -AutoSize | Out-String; Get-ClusterResource | ft Name,ResourceType,State -AutoSize | Out-String'
rt $IP_DC "$HERE/ps/sql-check.ps1" 120
[ -f "$HERE/reports/PR-validation-PASS.htm" ] && echo "validation report saved: runbook/reports/PR-validation-PASS.htm"
