#!/usr/bin/env bash
# usage: 03-iso-server.sh [up|down]
# Serves the kit's ISOs (iso/) to the guests over HTTP: nginx pod (hostNetwork, :8099) on ISO_NODE, files on an 8 GiB PVC.
# Why this way: the guests cannot reach this workstation (firewall), vendor sites block scripted downloads, and bulk data cannot be
# streamed through `kubectl exec`/`cp` on this cluster's API endpoint. The upload goes through Harvester's image-upload API instead
# (same endpoint kubectl uses; form field "chunk" for the backingimage backend, "file" would be for cdi), then a loader pod copies the image contents to the nginx volume.
source "$(dirname "$0")/lib.sh"
set -eo pipefail
FILES="virtio-win-0.1.302.iso:kit-virtio-win sql2016-sp2-x64-en.iso:kit-sql2016"
mode=${1:-up}
if [ "$mode" = down ]; then
  kubectl -n "$NS" delete pod isoserve isoload --ignore-not-found; kubectl -n "$NS" delete pvc isoserve-data --ignore-not-found
  for fi in $FILES; do kubectl -n "$NS" delete virtualmachineimage "${fi#*:}" --ignore-not-found; done
  rm -f "$HERE/.iso-base"; exit 0
fi
H="/usr/share/nginx/html"
serve_pod() { cat <<YAML | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata: {name: isoserve-data, namespace: $NS}
spec: {accessModes: [ReadWriteOnce], storageClassName: $ROOT_SC, resources: {requests: {storage: 8Gi}}}
---
apiVersion: v1
kind: Pod
metadata: {name: isoserve, namespace: $NS, labels: {app: isoserve}}
spec:
  hostNetwork: true
  nodeSelector: {kubernetes.io/hostname: $ISO_NODE}
  restartPolicy: Always
  containers:
  - name: nginx
    image: nginx:alpine
    command: [sh, -c]
    args:
    - |
      printf 'server { listen %s; root $H; autoindex on; sendfile on; }\n' "$ISO_PORT" > /etc/nginx/conf.d/default.conf
      exec nginx -g 'daemon off;'
    volumeMounts: [{name: d, mountPath: $H}]
  volumes: [{name: d, persistentVolumeClaim: {claimName: isoserve-data}}]
YAML
kubectl -n "$NS" wait --for=condition=Ready pod/isoserve --timeout=300s; }
all_present() {   # sha256 of each served file must equal iso/SHA256SUMS
  for fi in $FILES; do f=${fi%%:*}; want=$(awk -v f="$f" '$2==f{print $1}' "$ROOT/iso/SHA256SUMS")
    have=$(kubectl -n "$NS" exec isoserve -- sh -c "sha256sum $H/$f 2>/dev/null | cut -d' ' -f1" || true); [ -n "$want" ] && [ "$have" = "$want" ] || return 1; done; }
token_cfg() { python3 -c "import yaml,os;print('header = \"Authorization: Bearer '+yaml.safe_load(open(os.environ['KUBECONFIG']))['users'][0]['user']['token']+'\"')"; }
server()    { python3 -c "import yaml,os;print(yaml.safe_load(open(os.environ['KUBECONFIG']))['clusters'][0]['cluster']['server'])"; }
img_ready() { [ "$(kubectl -n "$NS" get virtualmachineimage "$1" -o jsonpath='{.spec.backend}' 2>/dev/null)" = backingimage ] && \
              [ "$(kubectl -n "$NS" get virtualmachineimage "$1" -o jsonpath='{.status.progress}' 2>/dev/null)" = 100 ] && \
              [ "$(kubectl -n "$NS" get virtualmachineimage "$1" -o jsonpath='{.status.size}')" = "$2" ]; }

say "ISO server on $ISO_NODE:$ISO_PORT"
serve_pod
if all_present; then echo "all ISOs already on the server"
else
  for fi in $FILES; do f=${fi%%:*}; img=${fi#*:}; size=$(stat -c %s "$ROOT/iso/$f")
    if img_ready "$img" "$size"; then echo "$img already uploaded"; continue; fi
    say "uploading $f as Harvester image $img ($((size/1048576)) MiB)"
    kubectl -n "$NS" delete virtualmachineimage "$img" --ignore-not-found --wait=true >/dev/null
    cat <<YAML | kubectl apply -f -
apiVersion: harvesterhci.io/v1beta1
kind: VirtualMachineImage
metadata: {name: $img, namespace: $NS}
spec: {displayName: $f, sourceType: upload, backend: backingimage, storageClassParameters: {numberOfReplicas: "2", staleReplicaTimeout: "30"}}
YAML
    sleep 5
    token_cfg | curl -sk --config - -m 1500 -o /dev/null -w 'upload HTTP %{http_code}\n' -F "chunk=@$ROOT/iso/$f" "$(server)/v1/harvester/harvesterhci.io.virtualmachineimages/$NS/$img?action=upload&size=$size" || echo "(curl ended early: judging by the image status instead)"
    for i in $(seq 1 120); do img_ready "$img" "$size" && break; sleep 5; done
    img_ready "$img" "$size" || die "image $img did not finish importing (kubectl -n $NS get virtualmachineimage $img -o yaml)"
  done
  say "copying image contents to the nginx volume"
  kubectl -n "$NS" delete pod isoserve --wait=true >/dev/null          # the volume is RWO: free it for the loader
  vols=""; devs=""; cmds=""; i=0
  for fi in $FILES; do f=${fi%%:*}; img=${fi#*:}; size=$(stat -c %s "$ROOT/iso/$f"); i=$((i+1)); gi=$(( size/1073741824 + 2 ))
    cat <<YAML | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata: {name: isosrc-$i, namespace: $NS}
spec: {accessModes: [ReadWriteOnce], volumeMode: Block, storageClassName: $(kubectl -n "$NS" get virtualmachineimage "$img" -o jsonpath='{.status.storageClassName}'), resources: {requests: {storage: ${gi}Gi}}}
YAML
    vols+="  - {name: s$i, persistentVolumeClaim: {claimName: isosrc-$i}}"$'\n'
    devs+="    - {name: s$i, devicePath: /dev/src$i}"$'\n'
    cmds+="head -c $size /dev/src$i > $H/$f; "
  done
  kubectl -n "$NS" delete pod isoload --ignore-not-found --wait=true >/dev/null
  cat <<YAML | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata: {name: isoload, namespace: $NS}
spec:
  nodeSelector: {kubernetes.io/hostname: $ISO_NODE}
  restartPolicy: Never
  containers:
  - name: c
    image: nginx:alpine
    command: [sh, -c, "$cmds sync; ls -l $H"]
    volumeMounts: [{name: d, mountPath: $H}]
    volumeDevices:
$devs
  volumes:
  - {name: d, persistentVolumeClaim: {claimName: isoserve-data}}
$vols
YAML
  for i in $(seq 1 180); do ph=$(kubectl -n "$NS" get pod isoload -o jsonpath='{.status.phase}'); [ "$ph" = Succeeded ] && break; [ "$ph" = Failed ] && break; sleep 5; done
  kubectl -n "$NS" logs isoload | tail -4; [ "$ph" = Succeeded ] || die "loader pod ended as $ph"
  kubectl -n "$NS" delete pod isoload --ignore-not-found >/dev/null; kubectl -n "$NS" delete pvc isosrc-1 isosrc-2 --ignore-not-found >/dev/null
  serve_pod
  all_present || die "files on the server do not match iso/SHA256SUMS"
fi
ip=$(kubectl get node "$ISO_NODE" -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
echo "http://$ip:$ISO_PORT" > "$HERE/.iso-base"
echo "ISO base URL: $(cat "$HERE/.iso-base")  (reachable from the guests, not necessarily from this workstation)"
