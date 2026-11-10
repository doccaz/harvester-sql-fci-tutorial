#!/usr/bin/env bash
# Domain controller: promote, reboot twice (Netlogon is not started after the first boot), then create SQLAdmins/sqlsvc/witness share.
source "$(dirname "$0")/lib.sh"
ip=$IP_DC
if wr $ip 'Get-Service NTDS -ErrorAction SilentlyContinue | % Status' 2>/dev/null | grep -q Running; then echo "already a DC, skipping promotion"
else
  say "promoting"; before=$(wr $ip '(gcim Win32_OperatingSystem).LastBootUpTime.ToString("o")' | tr -d '\r\n ')
  bg $ip "$HERE/ps/dc-promote.ps1" dcpromote
  # the forest install reboots the VM: wait for a new boot time
  t0=$SECONDS; while :; do sleep 15; now=$(wr $ip '(gcim Win32_OperatingSystem).LastBootUpTime.ToString("o")' 2>/dev/null | tr -d '\r\n ' || true); [ -n "$now" ] && [ "$now" != "$before" ] && break; (( SECONDS-t0 > 1500 )) && die "no reboot after promotion"; done
  wr $ip 'if(Test-Path C:\dcpromote.fail){Get-Content C:\dcpromote.fail}' | grep -q . && die "promotion failed (see C:\\dcpromote.log on the DC)"
  say "second reboot (Netlogon)"; reboot_wait $ip local
fi
for i in $(seq 1 30); do wr $ip 'Get-Service Netlogon | % Status' 2>/dev/null | grep -q Running && break; sleep 10; done
wr $ip 'Get-Service Netlogon | % Status' | grep -q Running || die "Netlogon not running"
say "domain objects"; wr $ip "$(render "$HERE/ps/dc-objects.ps1")"
