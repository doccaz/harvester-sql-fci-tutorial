#!/usr/bin/env bash
# Create the cluster (file-share witness), prepare the LUNs, run THE storage validation (before SQL), save the report.
source "$(dirname "$0")/lib.sh"
say "cluster";  rt $IP_N1 "$HERE/ps/cluster-create.ps1" 600
say "disks";    rt $IP_N1 "$HERE/ps/disks-prep.ps1" 300 | tee /tmp/.disks.$$
grep -q 'LUNS_VISIBLE=3' /tmp/.disks.$$ || { rm -f /tmp/.disks.$$; die "expected 3 LIO LUNs on n1"; }; rm -f /tmp/.disks.$$
say "Test-Cluster -Include Storage (about 5 minutes)"
out=$(rt $IP_N1 "$HERE/ps/validate.ps1" 1800); echo "$out"
echo "$out" | grep -q 'RESULT=PASS' || die "validation did not pass: open the report on n1 (C:\\Windows\\Cluster\\Reports). Do NOT continue to SQL."
say "pulling the report"
mkdir -p "$HERE/reports"
dwr $IP_N1 '[Convert]::ToBase64String([IO.File]::ReadAllBytes("C:\Windows\Cluster\Reports\PR-validation-PASS.htm"))' | tr -d '\r\n ' | base64 -d > "$HERE/reports/PR-validation-PASS.htm" && ls -l "$HERE/reports/PR-validation-PASS.htm"
