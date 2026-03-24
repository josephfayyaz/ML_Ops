# Learning Path

## Step 1: Understand The Cluster Layer

Start by reading the `kind` cluster config template. It shows how a laptop can emulate a small private cloud with:

- multiple Kubernetes nodes
- host-mounted project storage
- stable ingress ports

## Step 2: Understand Local Load Balancers

Study `MetalLB` next. In cloud Kubernetes, a cloud provider allocates service IPs. On a laptop, MetalLB fills that gap by assigning private addresses to `LoadBalancer` services from a pool you control.

## Step 3: Understand Service Ingress

Study `Istio` after MetalLB. Istio is responsible for:

- a single ingress entrypoint
- host-based routing
- service-mesh traffic policies

In this lab, `Istio` is how the browser reaches code-server, Katib, and the ML API.

## Step 4: Understand The Developer Workspace

The `code-server` pod is useful because it turns the cluster into a self-contained development environment. The repo is mounted into the pod, so you can edit the same project either from the laptop or from the browser IDE.

## Step 5: Understand ML Workload Packaging

The demo ML service shows the standard container path:

1. package the code with a Dockerfile
2. build the image locally
3. load it into `kind`
4. deploy it as a Kubernetes `Deployment`
5. expose it through a `Service`
6. route it with an Istio `VirtualService`

## Step 6: Understand Katib

Katib runs hyperparameter tuning as Kubernetes-native trial Jobs. In this lab:

- each trial runs the same container image
- the trial receives hyperparameters as command-line arguments
- the container prints `accuracy=<value>`
- Katib collects that metric from stdout and compares trials

## Step 7: Extend The Lab

Once the base platform works, the next good extensions are:

- replace the iris demo with your own training image
- add model registry and artifact storage
- add KServe for inference serving
- add Prometheus and Grafana for monitoring
- add TLS and real DNS instead of local `nip.io`

