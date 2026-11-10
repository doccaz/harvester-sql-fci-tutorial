#!/usr/bin/env bash
# usage: 11-failover-tests.sh planned | stop --yes | kill --yes
#   planned: Move-ClusterGroup.  stop: virtctl stop --force of the owner VM.  kill: kill -9 of that VM's QEMU.
# Measures client downtime from a probe on the DC (last OK -> first OK, includes the 2 s connect timeout).
source "$(dirname "$0")/lib.sh"
mode=${1:-}; [ "${2:-}" = --yes ] || [ "$mode" = planned ] || die "usage: $0 planned | stop --yes | kill --yes"
owner() { dwr $IP_N1 "(Get-ClusterGroup '$ROLE').OwnerNode.Name" | tr -d '\r\n '; }
healthy() { # both nodes Up and role Online
  dwr $IP_N1 "(@(Get-ClusterNode | ? State -eq Up).Count).ToString() + ' ' + (Get-ClusterGroup '$ROLE').State" 2>/dev/null | tr -d '\r' | grep -q '^2 Online'; }
wait_healthy() { for i in $(seq 1 60); do healthy && return 0; sleep 10; done; return 1; }
healthy || die "cluster not healthy before the test (need both nodes Up and the role Online)"
own=$(owner); [ "$own" = "$N1" ] && other=$N2 || other=$N1
echo "owner before: $own"
DUR=150; log="$(mktemp)"; sed "s/DURSEC/$DUR/" "$HERE/ps/probe.ps1" > "$HERE/.probe.ps1"
( rt $IP_DC "$HERE/.probe.ps1" 400 > "$log" ) & ppid=$!
sleep 25
case "$mode" in
  planned) dwr $IP_N1 "Move-ClusterGroup -Name '$ROLE' | Out-Null; 'moved'" ;;
  stop)    virtctl -n "$NS" stop "$own" --force --grace-period=0 ;;
  kill)    pod=$(kubectl -n "$NS" get pods -l vm.kubevirt.io/name="$own" -o name | tail -1)
           # the compute container has no pkill/pgrep: walk /proc. The pattern is anchored on /usr/bin/ and bracketed ([m]) so this shell cannot match itself
           kubectl -n "$NS" exec "$pod" -c compute -- sh -c 'for p in /proc/[0-9]*; do c=$(tr "\0" " " < $p/cmdline 2>/dev/null); case "$c" in /usr/bin/qemu-syste[m]*) kill -9 ${p#/proc/}; echo "killed qemu pid ${p#/proc/}";; esac; done' ;;
  *) kill $ppid; die "unknown mode";;
esac
wait $ppid; rm -f "$HERE/.probe.ps1"
python3 - "$log" <<'PY'
import sys,re,datetime as D
rows=[l.split(None,2) for l in open(sys.argv[1]) if re.match(r'\d\d:\d\d:\d\d\.\d+ (OK|FAIL)',l)]
t=lambda s:D.datetime.strptime(s,'%H:%M:%S.%f')
last_ok=None;down=None;res=[]
for ts,st,*h in rows:
    if st=='OK':
        if down: res.append((last_ok,ts,(t(ts)-t(last_ok)).total_seconds(),h[0].strip() if h else '')); down=None
        last_ok=ts
    elif last_ok and not down: down=ts
print('probe lines:',len(rows))
for a,b,d,h in res: print(f'outage: last OK {a} -> first OK {b} = {d:.1f} s, now served by {h}')
if not res: print('no outage seen (probe may have missed it: check the log)')
PY
rm -f "$log"
if [ "$mode" = stop ]; then echo "NOTE: a Force-Stopped VM may not restart by itself (harvester#11835)."; virtctl -n "$NS" start "$own" 2>/dev/null || true; fi
wait_healthy && echo "cluster healthy again, owner: $(owner)" || die "cluster did not return to both Up + Online: investigate before the next test (do NOT restart other nodes)"
