#!/usr/bin/env bash
# usage: gread.sh <vm> '<windows path>'   -- cat a guest file via qemu-guest-agent (no auth needed)
set -euo pipefail
NS=labs; vm=$1; path=$2
pod=$(kubectl -n $NS get pods -l vm.kubevirt.io/name="$vm" -o name | tail -1)
V="virsh --connect qemu+unix:///session?socket=/var/run/libvirt/virtqemud-sock"
q(){ kubectl -n $NS exec "$pod" -c compute -- $V qemu-agent-command ${NS}_$vm "$1"; }
j=$(python3 -c 'import json,sys;print(json.dumps({"execute":"guest-file-open","arguments":{"path":sys.argv[1],"mode":"r"}}))' "$path")
h=$(q "$j" | sed 's/.*"return":\([0-9]*\).*/\1/')
while :; do
  r=$(q "{\"execute\":\"guest-file-read\",\"arguments\":{\"handle\":$h,\"count\":60000}}")
  echo "$r" | python3 -c 'import sys,json,base64;d=json.load(sys.stdin)["return"];sys.stdout.buffer.write(base64.b64decode(d["buf-b64"]));sys.exit(0 if d["eof"] else 3)' && break || [ $? = 3 ] || break
done
q "{\"execute\":\"guest-file-close\",\"arguments\":{\"handle\":$h}}" >/dev/null
