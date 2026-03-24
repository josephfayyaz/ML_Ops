#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="${ROOT_DIR}/.state"
GENERATED_DIR="${ROOT_DIR}/infra/generated"

CLUSTER_NAME="${CLUSTER_NAME:-mlops-lab}"
KUBECONFIG_CONTEXT="kind-${CLUSTER_NAME}"
KIND_NETWORK_NAME="${KIND_NETWORK_NAME:-kind}"
KIND_NODE_IMAGE="${KIND_NODE_IMAGE:-kindest/node:v1.33.1}"

HOST_HTTP_PORT="${HOST_HTTP_PORT:-8080}"
HOST_HTTPS_PORT="${HOST_HTTPS_PORT:-8443}"
HOST_STATUS_PORT="${HOST_STATUS_PORT:-15021}"

ISTIO_HTTP_NODEPORT="${ISTIO_HTTP_NODEPORT:-30080}"
ISTIO_HTTPS_NODEPORT="${ISTIO_HTTPS_NODEPORT:-30443}"
ISTIO_STATUS_NODEPORT="${ISTIO_STATUS_NODEPORT:-30021}"

HOST_WORKSPACE_PATH="${HOST_WORKSPACE_PATH:-$ROOT_DIR}"
WORKSPACE_NODE_PATH="${WORKSPACE_NODE_PATH:-/workspaces/mlops-lab}"

METALLB_VERSION="${METALLB_VERSION:-0.15.3}"
ISTIO_VERSION="${ISTIO_VERSION:-1.29.1}"
KATIB_VERSION="${KATIB_VERSION:-v0.17.0}"
IRIS_IMAGE="${IRIS_IMAGE:-mlops-iris:0.1.0}"

CODE_SERVER_PASSWORD_FILE="${CODE_SERVER_PASSWORD_FILE:-$STATE_DIR/vscode-password.txt}"
CODE_SERVER_PASSWORD="${CODE_SERVER_PASSWORD:-}"

log() {
  printf "\n[%s] %s\n" "$(date +%H:%M:%S)" "$*"
}

require_bin() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required binary: $1" >&2
    exit 1
  fi
}

helm_release_exists() {
  helm status "$1" -n "$2" >/dev/null 2>&1
}

escape_sed() {
  printf "%s" "$1" | sed -e 's/[\/&|]/\\&/g'
}

render_template() {
  local template="$1"
  local output="$2"
  shift 2

  cp "$template" "$output"
  while (($#)); do
    local key="$1"
    local value="$2"
    shift 2
    sed -i.bak "s|${key}|$(escape_sed "$value")|g" "$output"
  done
  rm -f "${output}.bak"
}

kind_subnet() {
  docker network inspect "$KIND_NETWORK_NAME" -f '{{range .IPAM.Config}}{{println .Subnet}}{{end}}' \
    | awk '/^[0-9]+\./ {print; exit}'
}

calculate_metallb_range() {
  local subnet="$1"
  python3 - "$subnet" <<'PY'
import ipaddress
import sys

network = ipaddress.ip_network(sys.argv[1], strict=False)
end = ipaddress.ip_address(int(network.broadcast_address) - 6)
start = ipaddress.ip_address(int(end) - 49)
print(f"{start} {end}")
PY
}

ensure_password() {
  mkdir -p "$STATE_DIR"
  if [[ -n "$CODE_SERVER_PASSWORD" ]]; then
    printf "%s" "$CODE_SERVER_PASSWORD" > "$CODE_SERVER_PASSWORD_FILE"
    return
  fi

  if [[ -f "$CODE_SERVER_PASSWORD_FILE" ]]; then
    CODE_SERVER_PASSWORD="$(<"$CODE_SERVER_PASSWORD_FILE")"
    return
  fi

  CODE_SERVER_PASSWORD="$(
    python3 - <<'PY'
import secrets
import string

alphabet = string.ascii_letters + string.digits
print("".join(secrets.choice(alphabet) for _ in range(20)), end="")
PY
  )"
  printf "%s" "$CODE_SERVER_PASSWORD" > "$CODE_SERVER_PASSWORD_FILE"
}

ensure_cluster() {
  mkdir -p "$GENERATED_DIR"

  render_template \
    "$ROOT_DIR/infra/kind/cluster-config.template.yaml" \
    "$GENERATED_DIR/kind-cluster.yaml" \
    "__CLUSTER_NAME__" "$CLUSTER_NAME" \
    "__KIND_NODE_IMAGE__" "$KIND_NODE_IMAGE" \
    "__ISTIO_HTTP_NODEPORT__" "$ISTIO_HTTP_NODEPORT" \
    "__ISTIO_HTTPS_NODEPORT__" "$ISTIO_HTTPS_NODEPORT" \
    "__ISTIO_STATUS_NODEPORT__" "$ISTIO_STATUS_NODEPORT" \
    "__HOST_HTTP_PORT__" "$HOST_HTTP_PORT" \
    "__HOST_HTTPS_PORT__" "$HOST_HTTPS_PORT" \
    "__HOST_STATUS_PORT__" "$HOST_STATUS_PORT" \
    "__HOST_WORKSPACE_PATH__" "$HOST_WORKSPACE_PATH" \
    "__WORKSPACE_NODE_PATH__" "$WORKSPACE_NODE_PATH"

  if kind get clusters | grep -qx "$CLUSTER_NAME"; then
    log "kind cluster ${CLUSTER_NAME} already exists"
  else
    log "Creating kind cluster ${CLUSTER_NAME}"
    kind create cluster --config "$GENERATED_DIR/kind-cluster.yaml" --wait 180s
  fi

  kubectl config use-context "$KUBECONFIG_CONTEXT" >/dev/null
  kubectl wait --for=condition=Ready nodes --all --timeout=180s
}

install_metallb() {
  local subnet
  local pool_start
  local pool_end

  helm repo add metallb https://metallb.github.io/metallb >/dev/null 2>&1 || true
  helm repo update >/dev/null

  kubectl create namespace metallb-system --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  kubectl label namespace metallb-system \
    pod-security.kubernetes.io/enforce=privileged \
    pod-security.kubernetes.io/audit=privileged \
    pod-security.kubernetes.io/warn=privileged \
    --overwrite >/dev/null

  log "Installing MetalLB ${METALLB_VERSION}"
  if helm_release_exists metallb metallb-system; then
    log "MetalLB Helm release already present"
  else
    helm install metallb metallb/metallb \
      --namespace metallb-system \
      --version "$METALLB_VERSION" \
      --wait >/dev/null
  fi

  subnet="$(kind_subnet)"
  if [[ -n "${METALLB_POOL_START:-}" && -n "${METALLB_POOL_END:-}" ]]; then
    pool_start="$METALLB_POOL_START"
    pool_end="$METALLB_POOL_END"
  else
    read -r pool_start pool_end < <(calculate_metallb_range "$subnet")
  fi

  render_template \
    "$ROOT_DIR/manifests/metallb/ip-address-pool.template.yaml" \
    "$GENERATED_DIR/metallb-ip-pool.yaml" \
    "__METALLB_POOL_START__" "$pool_start" \
    "__METALLB_POOL_END__" "$pool_end"

  kubectl apply -f "$GENERATED_DIR/metallb-ip-pool.yaml" >/dev/null
  kubectl rollout status deployment/metallb-controller -n metallb-system --timeout=180s >/dev/null
  kubectl rollout status daemonset/metallb-speaker -n metallb-system --timeout=180s >/dev/null

  printf "METALLB_SUBNET=%s\nMETALLB_POOL_START=%s\nMETALLB_POOL_END=%s\n" \
    "$subnet" "$pool_start" "$pool_end" > "$STATE_DIR/metallb-range.env"
}

install_istio() {
  helm repo add istio https://istio-release.storage.googleapis.com/charts >/dev/null 2>&1 || true
  helm repo update >/dev/null

  log "Installing Istio base and control plane ${ISTIO_VERSION}"
  if helm_release_exists istio-base istio-system; then
    log "Istio base Helm release already present"
  else
    helm install istio-base istio/base \
      --namespace istio-system \
      --create-namespace \
      --version "$ISTIO_VERSION" \
      --set defaultRevision=default \
      --wait >/dev/null
  fi

  if helm_release_exists istiod istio-system; then
    log "Istiod Helm release already present"
  else
    helm install istiod istio/istiod \
      --namespace istio-system \
      --version "$ISTIO_VERSION" \
      --wait >/dev/null
  fi

  log "Installing Istio ingress gateway"
  if helm_release_exists istio-ingressgateway istio-ingress; then
    log "Istio ingress Helm release already present"
  else
    helm install istio-ingressgateway istio/gateway \
      --namespace istio-ingress \
      --create-namespace \
      --version "$ISTIO_VERSION" \
      --set service.type=NodePort \
      --wait >/dev/null
  fi

  kubectl patch service istio-ingressgateway -n istio-ingress --type merge -p "{
    \"spec\": {
      \"type\": \"NodePort\",
      \"ports\": [
        {\"name\": \"status-port\", \"port\": 15021, \"protocol\": \"TCP\", \"targetPort\": 15021, \"nodePort\": ${ISTIO_STATUS_NODEPORT}},
        {\"name\": \"http2\", \"port\": 80, \"protocol\": \"TCP\", \"targetPort\": 80, \"nodePort\": ${ISTIO_HTTP_NODEPORT}},
        {\"name\": \"https\", \"port\": 443, \"protocol\": \"TCP\", \"targetPort\": 443, \"nodePort\": ${ISTIO_HTTPS_NODEPORT}}
      ]
    }
  }" >/dev/null

  kubectl rollout status deployment/istio-ingressgateway -n istio-ingress --timeout=180s >/dev/null
}

install_katib() {
  local katib_ca_bundle=""

  log "Installing Katib ${KATIB_VERSION}"
  kubectl apply -k "github.com/kubeflow/katib.git/manifests/v1beta1/installs/katib-standalone?ref=${KATIB_VERSION}" >/dev/null

  kubectl rollout status deployment/katib-controller -n kubeflow --timeout=300s >/dev/null
  kubectl rollout status deployment/katib-db-manager -n kubeflow --timeout=300s >/dev/null
  kubectl rollout status deployment/katib-mysql -n kubeflow --timeout=300s >/dev/null
  kubectl rollout status deployment/katib-ui -n kubeflow --timeout=300s >/dev/null

  for _ in $(seq 1 30); do
    katib_ca_bundle="$(kubectl get secret -n kubeflow katib-webhook-cert -o jsonpath='{.data.tls\.crt}' 2>/dev/null || true)"
    if [[ -n "$katib_ca_bundle" ]]; then
      break
    fi
    sleep 2
  done

  if [[ -z "$katib_ca_bundle" ]]; then
    echo "Katib webhook certificate was not generated" >&2
    exit 1
  fi

  kubectl patch mutatingwebhookconfiguration katib.kubeflow.org --type=json -p="[
    {\"op\":\"replace\",\"path\":\"/webhooks/0/clientConfig/caBundle\",\"value\":\"${katib_ca_bundle}\"},
    {\"op\":\"replace\",\"path\":\"/webhooks/1/clientConfig/caBundle\",\"value\":\"${katib_ca_bundle}\"}
  ]" >/dev/null

  kubectl patch validatingwebhookconfiguration katib.kubeflow.org --type=json -p="[
    {\"op\":\"replace\",\"path\":\"/webhooks/0/clientConfig/caBundle\",\"value\":\"${katib_ca_bundle}\"}
  ]" >/dev/null
}

deploy_workloads() {
  # shellcheck disable=SC1090
  source "$STATE_DIR/metallb-range.env"

  log "Applying namespaces"
  kubectl apply -f "$ROOT_DIR/manifests/namespaces.yaml" >/dev/null

  log "Creating code-server password secret"
  kubectl -n dev-workspace create secret generic vscode-auth \
    --from-literal=password="$CODE_SERVER_PASSWORD" \
    --dry-run=client -o yaml | kubectl apply -f - >/dev/null

  log "Building sample ML image ${IRIS_IMAGE}"
  docker build -t "$IRIS_IMAGE" "$ROOT_DIR/apps/iris-service" >/dev/null
  kind load docker-image "$IRIS_IMAGE" --name "$CLUSTER_NAME" >/dev/null

  render_template \
    "$ROOT_DIR/manifests/vscode/deployment.yaml" \
    "$GENERATED_DIR/vscode-deployment.yaml" \
    "__WORKSPACE_NODE_PATH__" "$WORKSPACE_NODE_PATH"

  render_template \
    "$ROOT_DIR/manifests/iris/deployment.yaml" \
    "$GENERATED_DIR/iris-deployment.yaml" \
    "__IRIS_IMAGE__" "$IRIS_IMAGE"

  render_template \
    "$ROOT_DIR/manifests/iris/service.yaml" \
    "$GENERATED_DIR/iris-service.yaml" \
    "__IRIS_LOADBALANCER_IP__" "$METALLB_POOL_START"

  render_template \
    "$ROOT_DIR/manifests/katib/iris-experiment.yaml" \
    "$GENERATED_DIR/iris-experiment.yaml" \
    "__IRIS_IMAGE__" "$IRIS_IMAGE"

  log "Deploying code-server"
  kubectl apply -f "$ROOT_DIR/manifests/vscode/pvc.yaml" >/dev/null
  kubectl apply -f "$ROOT_DIR/manifests/vscode/service.yaml" >/dev/null
  kubectl apply -f "$GENERATED_DIR/vscode-deployment.yaml" >/dev/null

  log "Deploying iris API"
  kubectl apply -f "$GENERATED_DIR/iris-service.yaml" >/dev/null
  kubectl apply -f "$GENERATED_DIR/iris-deployment.yaml" >/dev/null

  log "Applying Istio routes"
  kubectl apply -f "$ROOT_DIR/manifests/istio/gateway.yaml" >/dev/null
  kubectl apply -f "$ROOT_DIR/manifests/istio/virtualservice-code-server.yaml" >/dev/null
  kubectl apply -f "$ROOT_DIR/manifests/istio/virtualservice-iris.yaml" >/dev/null
  kubectl apply -f "$ROOT_DIR/manifests/istio/virtualservice-katib.yaml" >/dev/null

  log "Starting Katib experiment"
  kubectl delete experiment -n katib-experiments iris-random-search --ignore-not-found=true --wait=true >/dev/null 2>&1 || true
  kubectl delete trials -n katib-experiments --all --ignore-not-found=true >/dev/null 2>&1 || true
  kubectl delete suggestions -n katib-experiments --all --ignore-not-found=true >/dev/null 2>&1 || true
  kubectl apply -f "$GENERATED_DIR/iris-experiment.yaml" >/dev/null

  kubectl rollout status deployment/vscode -n dev-workspace --timeout=300s >/dev/null
  kubectl rollout status deployment/iris-service -n mlops-apps --timeout=300s >/dev/null
}

validate_stack() {
  log "Running basic validation"
  kubectl get ipaddresspool -n metallb-system >/dev/null
  kubectl get gateway -n istio-ingress >/dev/null
  kubectl get experiment -n katib-experiments iris-random-search >/dev/null
  istioctl proxy-status >/dev/null 2>&1 || true

  curl -fsS "http://iris.127.0.0.1.nip.io:${HOST_HTTP_PORT}/healthz" >/dev/null
  curl -fsS "http://code.127.0.0.1.nip.io:${HOST_HTTP_PORT}" >/dev/null
  curl -fsS "http://katib.127.0.0.1.nip.io:${HOST_HTTP_PORT}/katib/" >/dev/null
}

print_summary() {
  # shellcheck disable=SC1090
  source "$STATE_DIR/metallb-range.env"

  cat <<EOF

Bootstrap complete.

Cluster:
  name: ${CLUSTER_NAME}
  context: ${KUBECONFIG_CONTEXT}

Endpoints:
  VS Code: http://code.127.0.0.1.nip.io:${HOST_HTTP_PORT}
  ML API:  http://iris.127.0.0.1.nip.io:${HOST_HTTP_PORT}
  Katib:   http://katib.127.0.0.1.nip.io:${HOST_HTTP_PORT}

Credentials:
  code-server password file: ${CODE_SERVER_PASSWORD_FILE}

MetalLB:
  subnet: ${METALLB_SUBNET}
  pool:   ${METALLB_POOL_START}-${METALLB_POOL_END}

Useful commands:
  kubectl get pods -A
  kubectl get experiments -n katib-experiments
  kubectl get trials -n katib-experiments
  istioctl proxy-status
EOF
}

main() {
  require_bin docker
  require_bin kubectl
  require_bin kind
  require_bin helm
  require_bin istioctl
  require_bin python3

  docker info >/dev/null
  mkdir -p "$STATE_DIR" "$GENERATED_DIR"

  ensure_password
  ensure_cluster
  install_metallb
  install_istio
  install_katib
  deploy_workloads
  validate_stack
  print_summary
}

main "$@"
