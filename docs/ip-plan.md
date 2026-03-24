# IP Plan

## Chosen Range

- Docker `kind` subnet: `172.19.0.0/16`
- MetalLB pool size: `50` addresses
- Recommended pool: `172.19.255.200-172.19.255.249`

## Full Address List

`172.19.255.200`, `172.19.255.201`, `172.19.255.202`, `172.19.255.203`, `172.19.255.204`, `172.19.255.205`, `172.19.255.206`, `172.19.255.207`, `172.19.255.208`, `172.19.255.209`

`172.19.255.210`, `172.19.255.211`, `172.19.255.212`, `172.19.255.213`, `172.19.255.214`, `172.19.255.215`, `172.19.255.216`, `172.19.255.217`, `172.19.255.218`, `172.19.255.219`

`172.19.255.220`, `172.19.255.221`, `172.19.255.222`, `172.19.255.223`, `172.19.255.224`, `172.19.255.225`, `172.19.255.226`, `172.19.255.227`, `172.19.255.228`, `172.19.255.229`

`172.19.255.230`, `172.19.255.231`, `172.19.255.232`, `172.19.255.233`, `172.19.255.234`, `172.19.255.235`, `172.19.255.236`, `172.19.255.237`, `172.19.255.238`, `172.19.255.239`

`172.19.255.240`, `172.19.255.241`, `172.19.255.242`, `172.19.255.243`, `172.19.255.244`, `172.19.255.245`, `172.19.255.246`, `172.19.255.247`, `172.19.255.248`, `172.19.255.249`

## Why This Range

- The worker and control-plane nodes currently use low addresses in the same subnet (`172.19.0.2` and `172.19.0.3`).
- Picking addresses near the end of the `/16` sharply reduces collision risk.
- The range is contiguous and easy to recognize when checking `kubectl get svc`.

## Recommended Reservation

- `172.19.255.206` is reserved for the `vscode` `LoadBalancer`.
- `172.19.255.207` is reserved for the `katib-public` `LoadBalancer`.
- `172.19.255.208` is reserved for the demo `iris-service` `LoadBalancer`.
- `172.19.255.200-172.19.255.205` and `172.19.255.209-172.19.255.249` stay available for future ML services.

## Host Reachability Caveat

Because this lab runs on Docker Desktop for macOS, these MetalLB IPs are not directly reachable from the host by default. This repo makes the reserved service IPs reachable by adding them as `lo0` aliases on macOS and binding the corresponding `NodePort`s to those same IPs through kind.
