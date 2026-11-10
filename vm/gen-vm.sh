#!/usr/bin/env bash
# Render Secret + VirtualMachine for a Windows lab VM cloned from the golden image.
# usage: gen-vm.sh <name> <ip> <mac> <node-hostname> <cpu> <mem> <disk> [lun-pvc ...]
# Output (stdout) is YAML; pipe to `kubectl apply -f -`. Reads ../env.local (never prints passwords to the terminal if redirected).
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$here/../env.local"
name=$1 ip=$2 mac=$3 node=$4 cpu=$5 mem=$6 disk=$7; shift 7
luns=("$@")
mask=255.255.255.0

disks=""; vols=""; i=0
for p in "${luns[@]}"; do
  i=$((i+1))
  disks+="          - name: shared-$p
            shareable: true
            errorPolicy: report
            lun: {bus: scsi, reservation: true}
"
  vols+="      - name: shared-$p
        persistentVolumeClaim: {claimName: $p}
"
done

cat <<YAML
apiVersion: v1
kind: Secret
metadata:
  name: $name-cloudinit
  namespace: $NS
stringData:
  userdata: |
    #cloud-config
    users:
    - name: Administrator
      passwd: $ADMIN_PASSWORD
      groups: [Administrators]
  networkdata: |
    version: 1
    config:
    - type: physical
      name: Ethernet
      mac_address: "$mac"
      subnets:
      - type: static
        address: $ip
        netmask: $mask
        gateway: $GATEWAY
        dns_nameservers: [${DNS:-$GATEWAY}]
---
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: $name
  namespace: $NS
  labels:
    harvesterhci.io/creator: harvester
    harvesterhci.io/os: windows
    sqllab: "true"
  annotations:
    harvesterhci.io/reservedMemory: 256Mi
    harvesterhci.io/volumeClaimTemplates: |-
      [{"metadata":{"name":"$name-rootdisk","annotations":{"harvesterhci.io/imageId":"$NS/win2022-cloudbase"}},
        "spec":{"accessModes":["ReadWriteMany"],"resources":{"requests":{"storage":"$disk"}},
        "volumeMode":"Block","storageClassName":"harvester-2replicas"}}]
spec:
  runStrategy: RerunOnFailure
  template:
    metadata:
      labels:
        harvesterhci.io/vmName: $name
        sqllab: "true"
    spec:
      nodeSelector:
        kubernetes.io/hostname: $node
      domain:
        cpu: {cores: $cpu}
        features:
          acpi: {enabled: true}
          apic: {enabled: true}
          smm: {enabled: true}
          hyperv:
            relaxed: {enabled: true}
            vapic: {enabled: true}
            spinlocks: {enabled: true, spinlocks: 8191}
            vpindex: {enabled: true}
            synic: {enabled: true}
            synictimer: {enabled: true}
            ipi: {enabled: true}
            runtime: {enabled: true}
            reset: {enabled: true}
        clock:
          utc: {}
          timer:
            hpet: {present: false}
            hyperv: {present: true}
            pit: {tickPolicy: delay}
            rtc: {tickPolicy: catchup}
        devices:
          disks:
          - name: rootdisk
            bootOrder: 1
            disk: {bus: virtio}
          - name: cloudinitdisk
            disk: {bus: sata}
${disks}          interfaces:
          - name: lan
            bridge: {}
            model: virtio
            macAddress: "$mac"
          inputs:
          - {bus: usb, name: tablet, type: tablet}
        resources:
          limits: {memory: $mem, cpu: $cpu}
      networks:
      - name: lan
        multus: {networkName: $LAN_NAD}
      volumes:
      - name: rootdisk
        persistentVolumeClaim: {claimName: $name-rootdisk}
      - name: cloudinitdisk
        cloudInitNoCloud:
          secretRef: {name: $name-cloudinit}
          networkDataSecretRef: {name: $name-cloudinit}
${vols}
YAML
