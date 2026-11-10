#!/usr/bin/env python3
"""usage: wr.py <ip> '<powershell>'  -- run PowerShell over WinRM (NTLM). Password from env.local, never printed."""
import sys, re, os, winrm
env = open(os.path.join(os.path.dirname(__file__), '..', 'env.local')).read()
pw = re.search(r'^ADMIN_PASSWORD=["\']?([^"\'\n]+)', env, re.M).group(1)
user = os.environ.get('WR_USER', 'Administrator')
s = winrm.Session(f'http://{sys.argv[1]}:5985/wsman', auth=(user, pw), transport='ntlm', operation_timeout_sec=90, read_timeout_sec=120)
cmd = "$ProgressPreference='SilentlyContinue'; " + sys.argv[2]
for k in ('ADMIN_PASSWORD','SQLSVC_PASSWORD','DSRM_PASSWORD'):
    m = re.search(r'^'+k+r'=["\']?([^"\'\n]+)', env, re.M)
    if m: cmd = cmd.replace('{{'+k+'}}', m.group(1))
r = s.run_ps(cmd)
sys.stdout.write(r.std_out.decode(errors='replace'))
err = r.std_err.decode(errors='replace')
if not err.startswith('#< CLIXML'): sys.stderr.write(err)
sys.exit(r.status_code)
