#!/usr/bin/env bash
# usage: setpw.sh <vm> [user]  -- set a local user's password to ADMIN_PASSWORD via qemu-guest-agent (no login needed)
set -euo pipefail
source "$(dirname "$0")/../env.local"
vm=$1; user=${2:-Administrator}
pod=$(kubectl -n "$NS" get pods -l vm.kubevirt.io/name="$vm" -o name | tail -1)
req=$(python3 -c 'import json,sys,base64;print(json.dumps({"execute":"guest-set-user-password","arguments":{"username":sys.argv[1],"password":base64.b64encode(sys.argv[2].encode()).decode(),"crypted":False}}))' "$user" "$ADMIN_PASSWORD")
kubectl -n "$NS" exec "$pod" -c compute -- virsh --connect 'qemu+unix:///session?socket=/var/run/libvirt/virtqemud-sock' qemu-agent-command "${NS}_$vm" "$req"
