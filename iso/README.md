# Installation media (not included)

Download these files yourself into this directory, then check them with `sha256sum -c SHA256SUMS`:

| File | Where from |
|---|---|
| `windows-server-2022-eval-x64-en.iso` | Microsoft Evaluation Center (Windows Server 2022, 180-day evaluation) |
| `sql2016-sp2-x64-en.iso` | SQL Server 2016 SP2 media (Developer or Evaluation edition) |
| `virtio-win-0.1.302.iso` | https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/archive-virtio/ |

The Microsoft files are subject to Microsoft's licence terms and are not redistributed here. If your downloads have different hashes (re-built or newer media), update `SHA256SUMS` and the file names in `runbook/lib.sh`.
