#!/usr/bin/env bash
# n1/n2: IPv6 off, vioscsi (replaces pvvxscsi), Failover-Clustering, reboot; then domain join, reboot.
source "$(dirname "$0")/lib.sh"
[ -n "$VIRTIO_ISO_URL" ] || die "no ISO URL: run 03-iso-server.sh first"
for v in $N1 $N2; do ip=$(vm_ip $v); say "$v prep"
  bg $ip "$HERE/ps/prep-node.ps1" prepnode
done
for v in $N1 $N2; do ip=$(vm_ip $v); wait_flag $ip prepnode local 2400 || die "$v prep failed"; done
for v in $N1 $N2; do ip=$(vm_ip $v); sleep 20; wait_winrm $ip local 600; done
say "driver check"
for v in $N1 $N2; do ip=$(vm_ip $v); wr $ip '(Get-CimInstance Win32_PnPSignedDriver | ? DeviceClass -eq "SCSIADAPTER" | % DeviceName) -join ";"' | tee /dev/stderr | grep -q 'Red Hat' || die "$v: vioscsi is not the SCSI driver (pvvxscsi still bound?)"; done
say "domain join"
for v in $N1 $N2; do ip=$(vm_ip $v); wr $ip "$(render "$HERE/ps/join.ps1")"; reboot_wait $ip local; done
for v in $N1 $N2; do wait_winrm $(vm_ip $v) domain 600; echo "$v: $(dwr $(vm_ip $v) 'whoami' | tr -d '\r')"; done
