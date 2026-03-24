# Deployment Runbook

## What The Bootstrap Script Does

`./scripts/bootstrap.sh` performs the full local platform setup:

1. Verifies local dependencies: `docker`, `kubectl`, `kind`, `helm`, `istioctl`, `python3`.
2. Renders a `kind` cluster config with:
   - one control-plane node
   - one worker node
   - host port mappings for Istio ingress
   - a bind mount of this repo into the cluster nodes for the code-server pod
3. Creates the `mlops-lab` cluster if it does not already exist.
4. Installs MetalLB 0.15.3 and configures a 50-address pool.
5. Installs Istio 1.29.1 with a fixed `NodePort` ingress gateway.
6. Installs Katib 0.17.0 in standalone mode.
7. Builds and loads the sample ML image into the cluster.
8. Deploys:
   - namespaces
   - code-server
   - sample ML API
   - Istio gateway and routes
   - Katib experiment
9. Runs basic validation curls against the exposed endpoints.

## Access Paths

- `http://code.127.0.0.1.nip.io:8080`
- `http://iris.127.0.0.1.nip.io:8080`
- `http://katib.127.0.0.1.nip.io:8080`

## Validation Commands

```bash
kubectl get pods -A
kubectl get svc -A
kubectl get experiments -n katib-experiments
kubectl get trials -n katib-experiments
kubectl get virtualservice,gateway -A
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

