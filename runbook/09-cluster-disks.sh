#!/usr/bin/env bash
# Add the LUNs to the cluster, name them, format SQLData (E:) and SQLLog (F:).
source "$(dirname "$0")/lib.sh"
rt $IP_N1 "$HERE/ps/cluster-disks.ps1" 600
