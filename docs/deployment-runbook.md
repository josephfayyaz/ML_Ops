# Deployment Runbook

## What The Bootstrap Script Does

`./scripts/bootstrap.sh` performs the full local platform setup:

1. Verifies local dependencies: `docker`, `kubectl`, `kind`, `helm`, `istioctl`, `python3`.
2. Verifies that the macOS `lo0` aliases for the external service IPs are present.
2. Renders a `kind` cluster config with:
   - one control-plane node
   - one worker node
   - host port mappings for external service IPs
   - a bind mount of this repo into the cluster nodes for the code-server pod
3. Creates the `mlops-lab` cluster if it does not already exist.
   If the existing cluster does not have the required external IP bindings, it recreates it once.
4. Installs MetalLB 0.15.3 and configures a 50-address pool.
5. Installs Istio 1.29.1 with a fixed `NodePort` ingress gateway.
6. Installs Katib 0.17.0 in standalone mode.
7. Builds and loads the sample ML image into the cluster.
8. Deploys:
   - namespaces
   - code-server
   - Katib public proxy
   - sample ML API
   - Katib experiment
9. Runs basic validation curls against the exposed endpoints.

## Access Paths

- `http://172.19.255.206`
- `http://172.19.255.207`
- `http://172.19.255.208`

## Required macOS Step

Before bootstrapping on a fresh boot, add the loopback aliases:

```bash
sudo ifconfig lo0 alias 172.19.255.206/32 up
sudo ifconfig lo0 alias 172.19.255.207/32 up
sudo ifconfig lo0 alias 172.19.255.208/32 up
```

## Validation Commands

```bash
kubectl get pods -A
kubectl get svc -A
kubectl get experiments -n katib-experiments
kubectl get trials -n katib-experiments
kubectl get ipaddresspool,l2advertisement -n metallb-system
istioctl proxy-status
```

## Clean Up

```bash
kind delete cluster --name mlops-lab
```

Generated local state is stored in:

- `.state/`
- `infra/generated/`
