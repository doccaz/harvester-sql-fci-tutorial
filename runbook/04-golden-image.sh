#!/usr/bin/env bash
# Check that the golden image exists and is complete. Building it is a long, partly manual job (see docs/golden-image.md).
source "$(dirname "$0")/lib.sh"
img=win2022-cloudbase
kubectl -n "$NS" get virtualmachineimage "$img" >/dev/null 2>&1 || die "image $NS/$img is missing. Build it as described in docs/golden-image.md, then re-run."
kubectl -n "$NS" get virtualmachineimage "$img" -o jsonpath='{.status.progress}% {.status.size}{"\n"}'
prog=$(kubectl -n "$NS" get virtualmachineimage "$img" -o jsonpath='{.status.progress}')
[ "${prog:-0}" = 100 ] || die "image not at 100%"
# The export is a Longhorn volume clone: a failed clone left an EMPTY image once ("No bootable devices").
pv=$(kubectl get pv -o json | python3 -c "
import sys,json
for p in json.load(sys.stdin)['items']:
    if p['spec'].get('claimRef',{}).get('name','').startswith('$img') or '$img' in str(p['metadata'].get('annotations',{})): print(p['metadata']['name'])" | head -1)
if [ -n "$pv" ]; then
  st=$(kubectl -n longhorn-system get volumes.longhorn.io "$pv" -o jsonpath='{.status.cloneStatus.state}' 2>/dev/null || true)
  echo "longhorn cloneStatus for $pv: ${st:-n/a}"; [ -z "$st" ] || [ "$st" = completed ] || die "clone not completed"
fi
echo "image looks complete. The real test is step 05: the DC must boot from it."
echo "NOT yet baked into the image (done per VM in step 07): vioscsi driver, Failover-Clustering, IPv6 off."
