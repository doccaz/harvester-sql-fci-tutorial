#!/usr/bin/env python3
"""usage: rt.py <ip> <script.ps1> [timeout_s]  -- run a PS script on a Windows lab VM as SQLLAB\\Administrator
via a scheduled task (real network credentials, no double-hop problem); prints its output. Secrets via {{NAME}} placeholders."""
import sys, re, os, time, winrm, uuid, base64
here = os.path.dirname(os.path.abspath(__file__))
env = open(os.path.join(here, '..', 'env.local')).read()
def sec(k):
    m = re.search(r'^'+k+r'=["\']?([^"\'\n]+)', env, re.M); return m.group(1) if m else None
ip, script = sys.argv[1], open(sys.argv[2]).read()
limit = int(sys.argv[3]) if len(sys.argv) > 3 else 300
for k in ('ADMIN_PASSWORD', 'SQLSVC_PASSWORD', 'DSRM_PASSWORD'):
    if sec(k): script = script.replace('{{'+k+'}}', sec(k))
tid = 'rt' + uuid.uuid4().hex[:8]
b64 = base64.b64encode(script.encode('utf-8')).decode()
wrapper = f"""$ProgressPreference='SilentlyContinue'
[IO.File]::WriteAllBytes('C:\\{tid}.ps1',[Convert]::FromBase64String((Get-Content C:\\{tid}.b64 -Raw))); Remove-Item C:\\{tid}.b64
$a = New-ScheduledTaskAction -Execute powershell.exe -Argument '-NoProfile -ExecutionPolicy Bypass -Command "& C:\\{tid}.ps1 *> C:\\{tid}.out; New-Item C:\\{tid}.done -Force | Out-Null"'
Register-ScheduledTask -TaskName {tid} -Action $a -User 'SQLLAB\\Administrator' -Password '{sec("ADMIN_PASSWORD")}' -RunLevel Highest | Out-Null
Start-ScheduledTask -TaskName {tid}
"""
s = winrm.Session(f'http://{ip}:5985/wsman', auth=('SQLLAB\\Administrator', sec('ADMIN_PASSWORD')), transport='ntlm', operation_timeout_sec=90, read_timeout_sec=120)
for i in range(0, len(b64), 1200):   # Windows limits a command line to ~8 KB: upload in chunks
    rr = s.run_ps(f"Add-Content -Path C:\\{tid}.b64 -Value '{b64[i:i+1200]}' -NoNewline")
    if rr.status_code != 0: sys.exit('rt.py: chunk upload failed: ' + rr.std_err.decode(errors='replace')[:300])
s.run_ps(wrapper)
t0 = time.time(); out = ''
while time.time() - t0 < limit:
    time.sleep(3)
    r = s.run_ps(f"if (Test-Path C:\\{tid}.done) {{ 'DONE' }}")
    if b'DONE' in r.std_out: break
r = s.run_ps(f"Get-Content C:\\{tid}.out -Raw -ErrorAction SilentlyContinue; Unregister-ScheduledTask -TaskName {tid} -Confirm:$false -ErrorAction SilentlyContinue; Remove-Item C:\\{tid}.* -ErrorAction SilentlyContinue")
sys.stdout.write(r.std_out.decode(errors='replace'))
