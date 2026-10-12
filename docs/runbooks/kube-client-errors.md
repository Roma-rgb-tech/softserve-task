# KubeClientErrors

**Severity:** warning

## What it means

A client of the Kubernetes API — Prometheus, an operator, a controller — has
received a 5xx for more than 1% of its requests. The client keeps retrying,
so the symptom is usually something slow or stale (a controller that does not
reconcile, a target Prometheus stops discovering) rather than an outage.

## Check

Which client, which target, which code:

```promql
sum by (job, instance, host, code, method) (rate(rest_client_requests_total{code=~"5.."}[5m]))
```

- `host` is where the failing requests go. A service address
  (`<name>.<namespace>.svc:443`) points at an admission webhook or an
  aggregated API; the API server's own address points at the control plane.
- What the API server itself answered with 500, by resource:

  ```promql
  sum by (group, resource, subresource, verb) (rate(apiserver_request_total{code="500"}[5m])) > 0
  ```

```bash
kubectl get apiservices | grep -v True                              # a broken aggregated API
kubectl get validatingwebhookconfigurations,mutatingwebhookconfigurations
kubectl get --raw='/readyz?verbose' | grep -v ok                     # a failing readiness check
```

## Mitigate

- A webhook whose pod is down blocks or fails every request it intercepts:
  fix or restart that pod (`kubectl -n <ns> get pods`).
- An APIService that is not `Available`: its backing service is down; the
  same.
- The control plane itself: on a managed cluster this belongs to the
  provider — check the cluster's Resource health / service health page and
  open a support case if it lasts.

## Known noise on managed clusters

On AKS the API server probes itself over loopback (`host="[::1]:443"`,
`GET /readyz`), and its instances answer 500 now and then. The chart's rule
counted those and paged at about 1.6% errors with nothing wrong in the
cluster and nothing anyone here could fix. On a managed cluster the chart's
rule is therefore disabled and replaced by one in
`cluster_platform/templates/platform-rules.yaml.j2` that leaves loopback
hosts out and waits fifteen minutes instead of the default.

## Escalate

A webhook or aggregated API you cannot bring back within 15 minutes, or
control-plane errors that keep growing: page the second line, and open a case
with the cloud provider for the control plane.
