# Step 0: build the Windows golden image

The VMs in this tutorial are cloned from a sysprepped Windows Server 2022 image with Cloudbase-Init (per-VM hostname, static IP, password at first boot). The image is built with the third-party project
[harvester-windows-cloudbase](https://github.com/abonillabeeche/harvester-windows-cloudbase) (Apache-2.0); this tutorial does not copy it. Read its README first, then follow the kubectl path with the changes below.

Tested with commit `4b84862`; `golden/fetch-reference.sh` clones it into `reference/`.

## Differences from the upstream defaults

| Item | Tutorial value |
|---|---|
| Windows | Server 2022 evaluation ISO, uploaded as a Harvester Image in namespace `labs` (find its short name and own StorageClass with the `kubectl get virtualmachineimage -A ...` command from the upstream README) |
| Namespace | `labs` (matches `NS` in `env.example`) instead of `default`: edit `namespace:` in `winbuild-vm.yaml` and `export-image.yaml`, **and `pvcNamespace:` in `export-image.yaml`** (it names the build disk's namespace) |
| Answer file | `Autounattend-2022.xml` (two-file secret, step 3a upstream) |
| Rootdisk StorageClass | `harvester-2replicas` (`ROOT_SC` in `env.example`), also as `targetStorageClassName` in `export-image.yaml` |
| **Exported image name** | **`win2022-cloudbase`** in namespace `labs`: edit `metadata.name`/`displayName` in `export-image.yaml` (upstream's 2022/2025 example names differ). `vm/gen-vm.sh` and runbook step 04 expect exactly this |
| Disk size | keep the 36Gi build disk; the VMs grow `C:` to 60 GiB at first boot |

## Outline (see upstream README for the full commands)

```bash
./golden/fetch-reference.sh && cd reference/harvester-windows-cloudbase/kubectl
# edit winbuild-vm.yaml + export-image.yaml as in the table above (fill every REPLACE_* value)
kubectl -n labs create secret generic winbuild-unattend \
  --from-file=autounattend.xml=Autounattend-2022.xml --from-file=bootstrap.ps1=bootstrap.ps1
kubectl apply -f winbuild-vm.yaml
# a brand-new VM reads "Stopped" for a moment, so wait for Running first or the next wait returns at once
kubectl -n labs wait --for=jsonpath='{.status.printableStatus}'=Running vm/winbuild --timeout=15m
kubectl -n labs wait --for=jsonpath='{.status.printableStatus}'=Stopped vm/winbuild --timeout=60m   # about 30 min
kubectl -n labs wait --for=delete vmi/winbuild --timeout=5m    # the export is refused while the build pod still exists
kubectl apply -f export-image.yaml
kubectl -n labs wait --for=jsonpath='{.status.conditions[?(@.type=="Imported")].status}'=True virtualmachineimage/win2022-cloudbase --timeout=15m
# "Imported" is reported BEFORE the disk copy has finished. Wait for the underlying volume clone too:
pv=$(kubectl -n labs get pvc win2022-cloudbase -o jsonpath='{.spec.volumeName}')
until [ "$(kubectl -n longhorn-system get volumes.longhorn.io $pv -o jsonpath='{.status.cloneStatus.state}')" = completed ]; do sleep 10; done
# only now remove the build VM (a failed or interrupted clone leaves an EMPTY image: "No bootable devices")
kubectl -n labs delete vm winbuild; kubectl -n labs delete secret winbuild-unattend
```

Then run `runbook/04-golden-image.sh` to check the image is complete.

Not baked into the image (done per VM by runbook step 07): the upstream virtio-win `vioscsi` driver (the VMDP `pvvxscsi` driver the image ships with does not pass the SCSI-3 PR test), Failover-Clustering, IPv6 off.
