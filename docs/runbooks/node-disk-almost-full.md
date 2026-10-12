# NodeDiskAlmostFull

**Severity:** warning

## What it means

A filesystem on a node has been fuller than the `monitoring.disk_percent`
threshold (85% by default) for ten minutes. At 100% the kubelet evicts pods,
images stop pulling and PostgreSQL stops writing.

## Check

```bash
kubectl describe node <node> | grep -A5 Conditions        # DiskPressure?
kubectl get pvc -A                                        # is it a volume rather than the node disk?
```

For the node disk, a debug pod on that node:

```bash
kubectl debug node/<node> -it --image=busybox -- sh -c 'df -h /host; du -sh /host/var/log /host/var/lib/containerd 2>/dev/null'
```

Usual suspects: container images that piled up, container logs, an emptyDir
that grows.

## Mitigate

- Images: the kubelet's image garbage collection frees space at its
  threshold; deleting unused pods' images makes room sooner.
- Logs: find the pod that logs the most and lower its log level.
- A database volume: expand the PVC (the storage class allows it) or the
  CloudNativePG `storage.size`.

## Escalate

Above 95% and still rising: page the second line before the kubelet starts
evicting.
