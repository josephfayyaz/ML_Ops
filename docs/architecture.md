# Architecture

## Overview

The platform simulates a small private-cloud MLOps environment for five students on a single laptop.

### Control Plane

- `kind` cluster
- `MetalLB` for Kubernetes `LoadBalancer` services
- `Istio` ingress gateway with host-based routing
- `Katib` for HPO
- `MinIO` for object storage

### User Plane

Each student gets:

- a dedicated Kubernetes namespace
- a dedicated browser IDE workspace Deployment and PVC
- a dedicated MinIO bucket
- dedicated Katib experiments and trials inside their namespace
- dedicated training, evaluation, and serving workloads

### Images

- `private-cloud-workspace`
  - browser IDE
  - Python toolchain
  - `kubectl`
  - MinIO client
  - project starter content
- `private-cloud-ml-runtime`
  - training
  - evaluation
  - inference serving
- `private-cloud-portal`
  - login
  - portal UI
  - dataset upload
  - Katib and artifact aggregation

### Networking

The ingress model is one real host IP on the laptop LAN interface and many virtual hosts.

Examples:

- `portal.<LAN-IP>.nip.io`
- `katib.<LAN-IP>.nip.io`
- `ws-student-1.<LAN-IP>.nip.io`
- `api-student-1.<LAN-IP>.nip.io`

This is more realistic than path-only localhost routing and closer to how a private cloud is normally operated.

### Storage Model

- source code and user edits: PVC mounted into the workspace
- datasets: MinIO bucket prefix `datasets/`
- trained models: MinIO bucket prefix `models/`
- evaluation reports: MinIO bucket prefix `evaluations/`

### GPU Model

Local laptop mode:

- `cpu`
- `nvidia-sim`
- `amd-sim`

Production-ready upgrade path:

- `nvidia-real` with NVIDIA GPU Operator / device plugin
- `amd-real` with AMD GPU Operator / device plugin

The local simulated GPU profiles use node labels and affinity to enforce real scheduling choices even though no NVIDIA or AMD hardware exists on this laptop.
