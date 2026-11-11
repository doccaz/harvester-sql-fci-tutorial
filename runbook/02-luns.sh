#!/usr/bin/env bash
# Shared LUNs: LIO targets (helm release, see lio/values-fci.yaml) -> PVs/PVCs in the lab namespace.
source "$(dirname "$0")/lib.sh"
say "LIO target (helm, chart in lio/chart)"
REL=lio-san; LNS=lio-san
if helm status $REL -n default >/dev/null 2>&1 && kubectl -n $LNS get pods 2>/dev/null | grep -q Running && helm get values $REL -n default 2>/dev/null | grep -q fci-sqllog; then
  echo "release $REL already deployed with the FCI targets: leaving it alone"
else
  helm upgrade --install $REL "$ROOT/lio/chart" -n default -f "$ROOT/lio/values-fci.yaml" --set namespace.name=$LNS --set nodeSelector."kubernetes\.io/hostname"=$NODE_A
fi
for i in $(seq 1 30); do kubectl -n $LNS get pods --no-headers 2>/dev/null | grep -v Running | grep -q . || break; sleep 5; done
kubectl -n $LNS get pods
say "PVs/PVCs"
PORTAL="${LIO_PORTAL:-$(kubectl get node "$NODE_A" -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')}"
[ -n "$PORTAL" ] || die "cannot find the IP of $NODE_A (set LIO_PORTAL in env.local)"
sed "s/__LIO_PORTAL__/$PORTAL/" "$ROOT/lio/fci-pv-pvc.yaml" | kubectl apply -f -
for p in fci-quorum fci-sqldata fci-sqllog; do
  kubectl -n "$NS" wait --for=jsonpath='{.status.phase}'=Bound pvc/$p --timeout=60s || die "PVC $p not Bound"
done
kubectl -n "$NS" get pvc fci-quorum fci-sqldata fci-sqllog
echo "LUN sizes must stay distinct (1/4/2 GiB): step 09 identifies the disks by size."
