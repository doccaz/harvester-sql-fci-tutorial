#!/usr/bin/env bash
# Clones the third-party golden-image project (Apache-2.0, not part of this repo) at the commit this tutorial was tested with.
set -euo pipefail
cd "$(dirname "$0")/.."
REF=reference/harvester-windows-cloudbase
[ -d $REF ] || git clone https://github.com/abonillabeeche/harvester-windows-cloudbase.git $REF
git -C $REF checkout -q 4b84862 || echo "WARN: tested commit 4b84862 not found; using the default branch (check docs/golden-image.md still applies)"
echo "$REF ready"
