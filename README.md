# Laptop MLOps Lab

This repository provisions a local MLOps platform on top of `kind` for a single macOS laptop running Docker Desktop.

It includes:

- `kind` as the local Kubernetes cluster
- `MetalLB` for a 50-address internal LoadBalancer pool
- `Istio` for ingress and service-mesh routing
- `Katib` for hyperparameter tuning
- a `code-server` pod as the browser-based VS Code workspace
- a sample ML application and Katib experiment to validate the stack

Tested on March 24, 2026 with:

- macOS 26.3.1 on arm64
- Docker Desktop 4.64.0
- `kind` 0.29.0
- Kubernetes 1.33.1
- MetalLB 0.15.3
- Istio 1.29.1
- Katib 0.17.0

## Quick Start

Run the full bootstrap:

```bash
./scripts/bootstrap.sh
```

Once the script completes, use:

- VS Code: `http://code.127.0.0.1.nip.io:8080`
- ML API: `http://iris.127.0.0.1.nip.io:8080`
- Katib UI: `http://katib.127.0.0.1.nip.io:8080`

The generated code-server password is stored in `.state/vscode-password.txt`.

## Important Networking Note

On Docker Desktop for macOS, the `kind` container network is not directly reachable from the host. That means MetalLB still works correctly inside the cluster, but the MetalLB IPs are not directly reachable from macOS by default.

For laptop access, this lab uses:

- MetalLB for in-cluster `LoadBalancer` behavior
- Istio ingress through host port `8080`
- fixed `NodePort` mappings from `kind` to the host

## Documentation

- [Architecture](docs/architecture.md)
- [Deployment Runbook](docs/deployment-runbook.md)
- [IP Plan](docs/ip-plan.md)
- [Learning Path](docs/learning-path.md)

