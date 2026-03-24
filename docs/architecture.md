# Architecture

```mermaid
flowchart LR
    Host["macOS laptop\nlo0 alias 172.19.255.206"] -->|172.19.255.206:80| Kind["kind control-plane"]
    Kind --> Ingress["Istio ingress gateway\nLB 172.19.255.206"]
    Ingress --> Code["code-server\nroute: /"]
    Ingress --> KatibUI["Katib UI\nroute: /katib/"]
    Ingress --> API["Iris ML API\nroute: /iris/"]
    Katib["Katib controller"] --> Trials["Katib trial Jobs\n(katib-experiments)"]
    MetalLB["MetalLB\n172.19.255.200-249"] --> Services["LoadBalancer services\ninside kind network"]
    Istio["Istio control plane"] --> Ingress
    Istio --> API
```

## Component Roles

- `kind` provides the local multi-node Kubernetes control plane.
- `MetalLB` supplies a private pool of service IPs for `LoadBalancer` services.
- `Istio` is the single public edge and also the in-cluster traffic-management layer.
- `code-server` provides a browser-accessible development workspace.
- `Katib` runs hyperparameter searches as Kubernetes Jobs.
- `iris-ml-api` is the demo workload used to prove the platform works end to end.

## Why The External IPs Work On macOS

Docker Desktop for macOS does not expose the `kind` bridge network directly to the host. This lab makes the MetalLB addresses reachable anyway by combining:

- an `lo0` alias on the host for `172.19.255.206`
- an Istio ingress `LoadBalancer` with the same IP
- `kind` host port mappings that bind port `80` on that IP to the Istio ingress `NodePort`
