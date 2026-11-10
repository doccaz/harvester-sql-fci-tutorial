#!/usr/bin/env bash
# usage: gexec.sh <vm> '<powershell command>'  -- runs via qemu-guest-agent, prints stdout/stderr, exit code
set -euo pipefail
source "$(dirname "$0")/../env.local"
vm=$1; cmd=$2
pod=$(kubectl -n "$NS" get pods -l vm.kubevirt.io/name="$vm" -o name | tail -1)
V="virsh --connect qemu+unix:///session?socket=/var/run/libvirt/virtqemud-sock"
enc=$(printf '%s' "$cmd" | iconv -t UTF-16LE | base64 -w0)
req=$(printf '{"execute":"guest-exec","arguments":{"path":"C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe","arg":["-NoProfile","-NonInteractive","-EncodedCommand","%s"],"capture-output":true}}' "$enc")
pid=$(kubectl -n "$NS" exec "$pod" -c compute -- $V qemu-agent-command "${NS}_$vm" "$req" | sed 's/.*"pid":\([0-9]*\).*/\1/')
for _ in $(seq 1 120); do
  out=$(kubectl -n "$NS" exec "$pod" -c compute -- $V qemu-agent-command "${NS}_$vm" "{\"execute\":\"guest-exec-status\",\"arguments\":{\"pid\":$pid}}")
  if echo "$out" | grep -q '"exited":true'; then
    echo "$out" | python3 -c 'import sys,json,base64
r=json.load(sys.stdin)["return"]
for k in("out-data","err-data"):
    if k in r: sys.stdout.write(base64.b64decode(r[k]).decode("utf-8","replace"))
sys.exit(r.get("exitcode",0))'
    exit $?
  fi
  sleep 2
done
echo "timeout" >&2; exit 124
