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

Add the required loopback aliases on macOS:

```bash
sudo ifconfig lo0 alias 172.19.255.206/32 up
sudo ifconfig lo0 alias 172.19.255.207/32 up
sudo ifconfig lo0 alias 172.19.255.208/32 up
```

Run the full bootstrap:

```bash
./scripts/bootstrap.sh
```

Once the script completes, use:

- VS Code: `http://172.19.255.206`
- Katib UI: `http://172.19.255.207`
- ML API: `http://172.19.255.208`

The generated code-server password is stored in `.state/vscode-password.txt`.

## Important Networking Note

On Docker Desktop for macOS, the `kind` container network is not directly reachable from the host. This lab works around that by:

- reserving `172.19.255.206-208` on `lo0`
- assigning the same addresses to Kubernetes `LoadBalancer` services via MetalLB
- mapping those service `NodePort`s onto the same host IPs through the kind control-plane container

## Documentation

- [Architecture](docs/architecture.md)
- [Deployment Runbook](docs/deployment-runbook.md)
- [IP Plan](docs/ip-plan.md)
- [Learning Path](docs/learning-path.md)
