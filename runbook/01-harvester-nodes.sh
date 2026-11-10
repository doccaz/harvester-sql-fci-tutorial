#!/usr/bin/env bash
# Lab-only: create /etc/target/pr on the node running the Linux LIO target (stands in for the SAN). A real SAN does not need this.
# Optional (WITH_MULTIPATH=1): scoped multipath CR on both workers.
source "$(dirname "$0")/lib.sh"
python3 - "$ROOT/lio/multipath-cloudinit.yaml" "${WITH_MULTIPATH:-0}" <<'PY' | kubectl apply -f -
import sys, re
docs = re.split(r'(?m)^---\s*$', open(sys.argv[1]).read())
keep = [d for d in docs if ('pr-lab-lio-aptpl-dir' in d) or (sys.argv[2] == '1' and 'name: pr-multipath' in d)]
print('\n---\n'.join(keep))
PY
cat <<MSG

The CloudInit CR only writes the file to /oem on the node; stages run at boot. To apply it NOW (on $NODE_A, as root):
    sudo elemental cloud-init -s boot /oem/96_lio_aptpl.yaml && ls -ld /etc/target/pr
(with WITH_MULTIPATH=1 also, on BOTH workers: sudo elemental cloud-init -s boot /oem/95_multipath.yaml)
MSG
echo "Confirm with: ssh $NODE_A 'ls -ld /etc/target/pr'  -- then continue with 02-luns.sh"
