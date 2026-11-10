#!/usr/bin/env bash
# Runs 00..10 in order, stopping at the first failure. Failover tests (10) are run separately.
set -e; cd "$(dirname "$0")"
for s in 00-prereqs 01-harvester-nodes 02-luns 03-iso-server 04-golden-image 05-vms 06-dc 07-nodes-prep-join 08-cluster 09-cluster-disks 10-sql 90-verify; do
  echo; echo "################ $s"; ./$s.sh
  [ "$s" = 01-harvester-nodes ] && { read -rp "Run the elemental cloud-init command on NODE_A (printed above), then press Enter... " _; }
done
