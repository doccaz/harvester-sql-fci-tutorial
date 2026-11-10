#!/usr/bin/env bash
# Shared helpers for the runbook scripts. Source, don't run.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/env.local"
: "${NODE_A:=node-a}"; : "${NODE_B:=node-b}"; : "${ISO_NODE:=$NODE_B}"; : "${ISO_PORT:=8099}"
export PATH="$ROOT/tools/bin:$PATH"       # optional: a virtctl dropped into tools/bin
# ISOs are served to the guests by an in-cluster nginx (step 03); it records its URL here.
[ -f "$HERE/.iso-base" ] && ISO_BASE="$(cat "$HERE/.iso-base")" || ISO_BASE=""
: "${SQL_ISO_URL:=${ISO_BASE:+$ISO_BASE/sql2016-sp2-x64-en.iso}}"
: "${VIRTIO_ISO_URL:=${ISO_BASE:+$ISO_BASE/virtio-win-0.1.302.iso}}"
PY="${PY:-$HERE/.venv/bin/python}"
DC=sqllab-dc1; N1=sqllab-fci-n1; N2=sqllab-fci-n2
ROLE='SQL Server (MSSQLSERVER)'
say()  { printf '\n=== %s\n' "$*"; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# Replace __NAME__ tokens and {{PASSWORD}} placeholders in a PS file (stdout). Never echo the result to a terminal.
render() {
  local s; s="$(cat "$1")"
  s="${s//__DOMAIN__/$DOMAIN}"; s="${s//__NETBIOS__/$NETBIOS}"; s="${s//__GATEWAY__/$GATEWAY}"
  s="${s//__IP_CLUSTER__/$IP_CLUSTER}"; s="${s//__IP_FCI__/$IP_FCI}"
  s="${s//__VIRTIO_URL__/$VIRTIO_ISO_URL}"; s="${s//__SQL_URL__/$SQL_ISO_URL}"
  s="${s//__VIRTIO_SHA__/$(awk '$2=="virtio-win-0.1.302.iso"{print $1}' "$ROOT/iso/SHA256SUMS")}"; s="${s//__SQL_SHA__/$(awk '$2=="sql2016-sp2-x64-en.iso"{print $1}' "$ROOT/iso/SHA256SUMS")}"; s="${s//__MODE__/${MODE:-}}"; s="${s//__WIPE__/${WIPE_LUNS:-0}}"
  s="${s//\{\{ADMIN_PASSWORD\}\}/$ADMIN_PASSWORD}"; s="${s//\{\{SQLSVC_PASSWORD\}\}/$SQLSVC_PASSWORD}"; s="${s//\{\{DSRM_PASSWORD\}\}/$DSRM_PASSWORD}"
  printf '%s' "$s"
}
# wr <ip> '<powershell>'   run inline over WinRM as local Administrator (before domain) or WR_USER
wr()  { local ip=$1; shift; "$PY" "$ROOT/vm/wr.py" "$ip" "$@"; }
# dwr <ip> '<powershell>'  run inline as the domain admin
dwr() { local ip=$1; shift; WR_USER="$NETBIOS\\Administrator" "$PY" "$ROOT/vm/wr.py" "$ip" "$@"; }
# rt <ip> <file.ps1> [timeout]  run a (rendered) script as a domain-admin scheduled task: no double hop
rt()  { local ip=$1 f=$2 t=${3:-600} tmp; tmp="$(mktemp)"; render "$f" >"$tmp"; "$PY" "$ROOT/vm/rt.py" "$ip" "$tmp" "$t"; local rc=$?; rm -f "$tmp"; return $rc; }
# bg <ip> <file.ps1> <name> [domain]  run a script detached as SYSTEM (survives the WinRM session and reboots); writes C:\<name>.done / .fail
bg() {
  local ip=$1 f=$2 name=$3 runner=wr b64 i
  [ "${4:-}" = domain ] && runner=dwr
  b64="$(render "$f" | base64 -w0)"
  # Windows limits a command line to ~8 KB: upload the script in small chunks (and clear stale flags first)
  $runner "$ip" "Remove-Item C:\\$name.done,C:\\$name.fail,C:\\$name.b64 -ErrorAction SilentlyContinue; 'cleared'" >/dev/null || die "bg: cannot reach $ip"
  for ((i=0; i<${#b64}; i+=1200)); do
    $runner "$ip" "Add-Content -Path C:\\$name.b64 -Value '${b64:i:1200}' -NoNewline" >/dev/null || die "bg: chunk upload to $ip failed"
  done
  $runner "$ip" "[IO.File]::WriteAllBytes('C:\\$name.ps1',[Convert]::FromBase64String((Get-Content C:\\$name.b64 -Raw))); Remove-Item C:\\$name.b64
Unregister-ScheduledTask -TaskName $name -Confirm:\$false -ErrorAction SilentlyContinue
Register-ScheduledTask -TaskName $name -Action (New-ScheduledTaskAction -Execute powershell.exe -Argument '-NoProfile -ExecutionPolicy Bypass -File C:\\$name.ps1') -Principal (New-ScheduledTaskPrincipal -UserId SYSTEM -RunLevel Highest) | Out-Null
Start-ScheduledTask -TaskName $name; 'started $name'" || die "bg: could not start $name on $ip"
}
# wait_flag <ip> <name> [domain] [timeout_s]   wait for C:\<name>.done (ok) or .fail (error); survives reboots
wait_flag() {
  local ip=$1 name=$2 runner=wr t=${4:-1800} t0=$SECONDS out
  [ "${3:-}" = domain ] && runner=dwr
  while (( SECONDS - t0 < t )); do
    out="$($runner "$ip" "if(Test-Path C:\\$name.done){'DONE'}elseif(Test-Path C:\\$name.fail){'FAIL'}" 2>/dev/null || true)"
    case "$out" in *DONE*) return 0;; *FAIL*) echo "--- C:\\$name.log:"; $runner "$ip" "Get-Content C:\\$name.log -Tail 25" 2>/dev/null || true; return 1;; esac
    sleep 10
  done
  echo "timeout waiting for $name on $ip"; return 1
}
# wait_winrm <ip> [domain] [timeout_s]   wait until WinRM answers
wait_winrm() {
  local ip=$1 runner=wr t=${3:-600} t0=$SECONDS
  [ "${2:-}" = domain ] && runner=dwr
  until $runner "$ip" 'hostname' >/dev/null 2>&1; do (( SECONDS - t0 > t )) && die "WinRM on $ip did not come back"; sleep 8; done
}
# reboot_wait <ip> <domain|local>   reboot and wait for it to come back with a new boot time
reboot_wait() {
  local ip=$1 mode=${2:-local} r=wr; [ "$mode" = domain ] && r=dwr
  local before; before="$($r "$ip" '(gcim Win32_OperatingSystem).LastBootUpTime.ToString("o")' | tr -d '\r\n ')"
  $r "$ip" 'shutdown /r /t 3 /f' >/dev/null 2>&1 || true
  local t0=$SECONDS now
  while (( SECONDS - t0 < 600 )); do
    sleep 10; now="$($r "$ip" '(gcim Win32_OperatingSystem).LastBootUpTime.ToString("o")' 2>/dev/null | tr -d '\r\n ' || true)"
    [ -n "$now" ] && [ "$now" != "$before" ] && return 0
  done
  die "$ip did not reboot"
}
vm_ip() { case "$1" in $DC) echo "$IP_DC";; $N1) echo "$IP_N1";; $N2) echo "$IP_N2";; esac; }
