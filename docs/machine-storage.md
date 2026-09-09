# Disks and first boot

## More than one disk

A VM's `boot_disk` is where the system lives. Anything that should survive
independently of it - a data directory, a volume that is meant to be resized or
snapshotted on its own schedule - is declared beside it:

```json
"history": {
  "role": "history",
  "boot_disk": { "size_gb": 20, "type": "balanced" },
  "extra_disks": [
    { "name": "data", "size_gb": 20, "type": "balanced", "mount_path": "/var/lib/oilscope" }
  ]
}
```

`type` is the same portable class the boot disk uses - `standard`, `balanced` or
`ssd` - resolved through the catalog, so the configuration never names
`pd-balanced` or `gp3` directly.

The list turns into blocks rather than into separate resources per cloud,
because the number of disks is not known when the module is written:

```hcl
dynamic "attached_disk" {
  for_each = each.value.extra_disks

  content {
    source      = google_compute_disk.extra["${each.key}/${attached_disk.value.name}"].id
    device_name = attached_disk.value.name
    mode        = "READ_WRITE"
  }
}
```

On GCP the disk is a resource of its own, `google_compute_disk`, and the block
only attaches it - so it outlives the machine, which is the usual reason for
wanting a second disk at all. On AWS the equivalent is `ebs_block_device`, whose
volumes are created with the instance.

## cloud-init

Terraform renders one cloud-config document per VM from
`modules/shared/cloudinit` and hands it to the cloud: metadata key `user-data`
on Compute Engine, `user_data` on EC2. The same document is used on both sides,
which is the point of writing it as cloud-init rather than as a startup script.

A machine that declares nothing to do at first boot gets no user data at all,
rather than an empty document.

What the document does:

- writes the table of disks the machine is supposed to have;
- writes `/usr/local/sbin/oilscope-prepare-disks` and runs it;
- runs the commands from `ci.commands`, in order;
- writes and runs `ci.startup_script`, when the configuration gives one.

The commands are the point of the block. A machine that needs one package, or
one file, or one service enabled - and nothing else worth a role - says so in
its own entry in the configuration:

```json
"history": {
  "ci": {
    "commands": [
      "apt-get update -qq",
      "apt-get install -y -qq jq"
    ]
  }
}
```

## Finding the right disk

Neither cloud gives the guest a dependable name for an extra disk. On Compute
Engine they arrive as `/dev/sdb` and up. On EC2 Nitro the device name handed to
the API is not what appears in the guest at all: the volumes turn up as NVMe
namespaces, numbered in an order that has nothing to do with the request.

So the script does not go looking for a device name. It matches on the one
property both clouds preserve - the size - and it only ever writes to a device
that is completely blank: no partition table, no filesystem, not mounted. Then
it creates the filesystem, adds an `/etc/fstab` entry by UUID and mounts it.

Running it twice does nothing the second time: a disk already mounted at its
destination is left alone. That matters because cloud-init runs again on some
reboots, and because the disk is the one thing on the machine that is not
supposed to be disposable.
