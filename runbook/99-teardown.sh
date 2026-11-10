#!/usr/bin/env bash
# Deletes the three Windows VMs, their root disks and cloud-init secrets. NOT the LUNs, PVs, golden image or node config.
source "$(dirname "$0")/lib.sh"
[ "${1:-}" = --yes ] || die "this deletes $DC $N1 $N2 and their disks. Re-run with --yes"
for v in $DC $N1 $N2; do kubectl -n "$NS" delete vm "$v" --wait=false; kubectl -n "$NS" delete secret "$v-cloudinit" --ignore-not-found; done
sleep 20; kubectl -n "$NS" delete pvc "$DC-rootdisk" "$N1-rootdisk" "$N2-rootdisk" --ignore-not-found
echo "The LUNs keep their data AND their SCSI-3 reservations (held for the deleted cluster). Before a rebuild set WIPE_LUNS=1 in env.local: step 08 then clears the reservations (Clear-ClusterDiskReservation) and the disks. Without it, writes fail and Test-Cluster reports everything Not Applicable."
