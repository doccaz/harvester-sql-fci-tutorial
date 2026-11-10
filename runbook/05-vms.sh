#!/usr/bin/env bash
# Create dc1, n1, n2 from the golden image; set the Administrator password through the guest agent (the cloud-config one is a first-boot race).
source "$(dirname "$0")/lib.sh"
V="$ROOT/vm"
say "dc1";  DNS="$GATEWAY"   "$V/gen-vm.sh" $DC $IP_DC 02:00:00:5a:11:70 $NODE_A 2 6Gi 60Gi | kubectl apply -f -
say "n1";   DNS="$IP_DC"     "$V/gen-vm.sh" $N1 $IP_N1 02:00:00:5a:11:71 $NODE_A 4 12Gi 60Gi fci-quorum fci-sqldata fci-sqllog | kubectl apply -f -
say "n2";   DNS="$IP_DC"     "$V/gen-vm.sh" $N2 $IP_N2 02:00:00:5a:11:72 $NODE_B 4 12Gi 60Gi fci-quorum fci-sqldata fci-sqllog | kubectl apply -f -
for v in $DC $N1 $N2; do
  kubectl -n "$NS" wait --for=condition=Ready vmi/$v --timeout=900s || die "$v not Ready (console: 'No bootable devices' = empty golden image, re-check step 04)"
done
say "waiting for the guest agent, then setting passwords"
for v in $DC $N1 $N2; do
  for i in $(seq 1 60); do bash "$ROOT/vm/setpw.sh" $v >/dev/null 2>&1 && break; sleep 10; done
done
for v in $DC $N1 $N2; do wait_winrm "$(vm_ip $v)" local 900; echo "$v: WinRM ok as $(wr "$(vm_ip $v)" 'whoami' | tr -d '\r')"; done
