# Private Cloud MLOps Lab

This repository provisions a laptop-scale private-cloud simulation for five students.

What it deploys:

- `kind` Kubernetes cluster with one control plane and three worker nodes
- `MetalLB` for `LoadBalancer` semantics inside the cluster
- `Istio` ingress with host-based routing on the laptop's LAN IP
- `Katib` for per-student hyperparameter optimization
- `MinIO` for datasets, models, and evaluation reports
- custom browser IDE workspaces with Python, Kubernetes, and MinIO tooling
- per-student training, evaluation, and model-serving workloads
- a login-protected portal for datasets, Katib results, artifacts, and service links

## Access Model

The platform is exposed on the laptop's LAN IP, not `127.0.0.1`.

By default the bootstrap script detects the current LAN IP and uses hostnames like:

- `http://portal.<LAN-IP>.nip.io`
- `http://katib.<LAN-IP>.nip.io`
- `http://ws-student-1.<LAN-IP>.nip.io`
- `http://api-student-1.<LAN-IP>.nip.io`

This is the closest practical local equivalent to a private-cloud ingress without requiring root access for host IP aliases.

MetalLB still assigns a real `LoadBalancer` IP to the Istio ingress service inside the kind network. On macOS, user traffic reaches the platform through the laptop LAN IP and kind port publishing, because Docker Desktop does not expose those inner bridge addresses directly on the host network.

## Default Users

The default credentials are defined in [config/users.yaml](/Users/youseffayyaz/Documents/GitHub/ML_Ops/config/users.yaml).

- `admin` can see all students.
- each `student-*` user can only see their own workspace, datasets, Katib results, artifacts, and serving endpoint.

## GPU Profiles

This laptop does not have NVIDIA or AMD GPUs. The lab therefore supports:

- `cpu`
- `nvidia-sim`
- `amd-sim`

The simulated GPU profiles schedule jobs onto dedicated labeled worker nodes so the placement is real and visible in Kubernetes. When you move to a Linux server with real GPUs, you can switch the same project model to `nvidia-real` or `amd-real` and add the corresponding operator/device plugin.

## Quick Start

```bash
./scripts/bootstrap.sh
```

The script will print the portal, Katib, workspace, and inference URLs.

## Student Workflow

1. Log into the portal.
2. Upload a dataset to your own bucket.
3. Open your own browser IDE workspace.
4. Edit `project.yaml` and the Python files under `student_lab/`.
5. Run `python -m student_lab.render_manifests`.
6. Run `kubectl apply -f manifests/rendered/katib-experiment.yaml`.
7. Wait for Katib to finish and inspect best hyperparameters in the portal or Katib UI.
8. Run `kubectl create -f manifests/rendered/train-job.yaml`.
9. Run `kubectl create -f manifests/rendered/evaluate-job.yaml`.
10. Run `kubectl apply -f manifests/rendered/serve-deployment.yaml`.
11. Send inference requests to your own API hostname.

## Cleanup

```bash
./scripts/teardown.sh
```

This removes the cluster and the project-specific Docker images.
