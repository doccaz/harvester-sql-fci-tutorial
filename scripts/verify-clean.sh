#!/usr/bin/env bash
# Pre-publish check: fails if the tree contains anything that looks personal, environment-specific or secret.
# Edit PATTERNS (and add your own names/hosts) before using it for a new publication.
cd "$(dirname "$0")/.." || exit 1
PATTERNS='192\.168\.86\.|harv0[0-9]lab|/home/|Projetos|erico|mendon|@gmail|image-[a-z0-9]*[0-9][a-z0-9]*|lh-[0-9a-f]{8}-[0-9a-f]{4}|BEGIN (RSA|OPENSSH|PRIVATE)|eyJ[A-Za-z0-9_-]{20,}|token: |client-key-data|customer'
hits=$(grep -rInEi "$PATTERNS" . --exclude-dir=.git --exclude-dir=.venv --exclude-dir=reference --exclude=verify-clean.sh --exclude=LICENSE)
bad=0; [ -n "$hits" ] && { echo "Suspicious content:"; echo "$hits"; bad=1; }
for f in env.local runbook/.iso-base; do [ -e "$f" ] && { echo "must not be published: $f"; bad=1; }; done
find . -name '*.iso' -o -name '*.htm' -o -name '*.kubeconfig' -o -name 'kubeconfig*' | grep -v '^./.git/' | sed 's/^/must not be published: /' | grep . && bad=1
command -v gitleaks >/dev/null && { gitleaks detect --no-git --source . -q || bad=1; } || echo "(gitleaks not installed: run it too)"
[ $bad = 0 ] && echo "clean" || { echo "NOT clean"; exit 1; }
