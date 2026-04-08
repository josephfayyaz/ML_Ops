#!/usr/bin/env bash

set -euo pipefail

detect_public_host_ip() {
  local primary_interface=""
  primary_interface="$(route -n get default 2>/dev/null | awk '/interface: / {print $2; exit}')"
  if [[ -n "$primary_interface" ]]; then
    ipconfig getifaddr "$primary_interface" 2>/dev/null && return 0
  fi
  ipconfig getifaddr en0 2>/dev/null && return 0
  ipconfig getifaddr en1 2>/dev/null && return 0
  printf '127.0.0.1'
}

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="${ROOT_DIR}/.state"
GENERATED_DIR="${ROOT_DIR}/infra/generated"

CLUSTER_NAME="${CLUSTER_NAME:-private-cloud-lab}"
KUBECONFIG_CONTEXT="kind-${CLUSTER_NAME}"
KIND_NODE_IMAGE="${KIND_NODE_IMAGE:-kindest/node:v1.33.1}"

PUBLIC_HOST_IP="${PUBLIC_HOST_IP:-$(detect_public_host_ip)}"
PUBLIC_BASE_DOMAIN="${PUBLIC_BASE_DOMAIN:-${PUBLIC_HOST_IP}.nip.io}"
HTTP_NODEPORT="${HTTP_NODEPORT:-30080}"
HTTPS_NODEPORT="${HTTPS_NODEPORT:-30443}"

METALLB_VERSION="${METALLB_VERSION:-0.15.3}"
ISTIO_VERSION="${ISTIO_VERSION:-1.29.1}"
KATIB_VERSION="${KATIB_VERSION:-v0.17.0}"
MINIO_CHART_VERSION="${MINIO_CHART_VERSION:-5.4.0}"

WORKSPACE_IMAGE="${WORKSPACE_IMAGE:-private-cloud-workspace:2.1.0}"
RUNTIME_IMAGE="${RUNTIME_IMAGE:-private-cloud-ml-runtime:2.1.0}"
PORTAL_IMAGE="${PORTAL_IMAGE:-private-cloud-portal:2.0.3}"

WORKSPACE_IMAGE_REVISION=""
RUNTIME_IMAGE_REVISION=""
PORTAL_IMAGE_REVISION=""

PLATFORM_NAMESPACE="${PLATFORM_NAMESPACE:-platform}"
MINIO_RELEASE="${MINIO_RELEASE:-minio}"
PORTAL_NAME="${PORTAL_NAME:-portal}"
WORKSPACE_PVC_NAME="${WORKSPACE_PVC_NAME:-workspace-home}"
WORKSPACE_SERVICE_ACCOUNT="${WORKSPACE_SERVICE_ACCOUNT:-student-runner}"
WORKSPACE_STORAGE_SIZE="${WORKSPACE_STORAGE_SIZE:-10Gi}"
WORKSPACE_CPU_REQUEST="${WORKSPACE_CPU_REQUEST:-500m}"
WORKSPACE_MEMORY_REQUEST="${WORKSPACE_MEMORY_REQUEST:-1Gi}"
WORKSPACE_CPU_LIMIT="${WORKSPACE_CPU_LIMIT:-2}"
WORKSPACE_MEMORY_LIMIT="${WORKSPACE_MEMORY_LIMIT:-4Gi}"
MINIO_STORAGE_SIZE="${MINIO_STORAGE_SIZE:-25Gi}"
COMPUTE_MODE="${COMPUTE_MODE:-simulated}"
USERS_FILE="${ROOT_DIR}/config/users.yaml"
SESSION_SECRET_FILE="${STATE_DIR}/portal-session-secret.txt"
MINIO_ROOT_USER_FILE="${STATE_DIR}/minio-root-user.txt"
MINIO_ROOT_PASSWORD_FILE="${STATE_DIR}/minio-root-password.txt"
INGRESS_LB_IP_FILE="${STATE_DIR}/ingress-lb-ip.txt"

STUDENTS=(student-1 student-2)

log() {
  printf "\n[%s] %s\n" "$(date +%H:%M:%S)" "$*"
}

require_bin() {
  command -v "$1" >/dev/null 2>&1 || { echo "Missing required binary: $1" >&2; exit 1; }
}

random_text() {
  python3 - "$1" <<'PY'
import secrets
import string
import sys

length = int(sys.argv[1])
alphabet = string.ascii_letters + string.digits
print("".join(secrets.choice(alphabet) for _ in range(length)), end="")
PY
}

wait_for_loadbalancer_ip() {
  local namespace="$1"
  local service="$2"
  local ip=""
  local attempt=0

  while [[ $attempt -lt 180 ]]; do
    ip="$(kubectl get service "$service" -n "$namespace" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"
    if [[ -n "$ip" ]]; then
      printf "%s" "$ip"
      return 0
    fi
    sleep 1
    attempt=$((attempt + 1))
  done

  echo "Timed out waiting for ${namespace}/${service} to receive a MetalLB IP" >&2
  return 1
}

wait_for_http_status() {
  local host="$1"
  local url="$2"
  local accepted_pattern="$3"
  local status=""
  local attempt=0

  while [[ $attempt -lt 60 ]]; do
    status="$(curl -sS -o /dev/null -w '%{http_code}' -H "Host: ${host}" "${url}" 2>/dev/null || true)"
    if [[ "$status" =~ ^(${accepted_pattern})$ ]]; then
      return 0
    fi
    sleep 2
    attempt=$((attempt + 1))
  done

  echo "Timed out waiting for ${host} (${url}) to return one of: ${accepted_pattern}. Last status: ${status}" >&2
  return 1
}

prepull_kind_image() {
  local image="$1"
  local node=""

  while IFS= read -r node; do
    [[ -n "$node" ]] || continue
    docker exec "$node" crictl pull "$image" >/dev/null
  done < <(kind get nodes --name "$CLUSTER_NAME")
}

ensure_secret_file() {
  local path="$1"
  local length="$2"
  mkdir -p "$(dirname "$path")"
  if [[ ! -f "$path" ]]; then
    random_text "$length" > "$path"
  fi
}

student_password() {
  awk -v target="$1" '
    $1 == "-" && $2 == "username:" { user = $3 }
    $1 == "password:" && user == target { print $2; exit }
  ' "$USERS_FILE"
}

workspace_token() {
  printf "%s" "$(student_password "$1")" | sed 's/[^0-9A-Za-z-]/-/g'
}

student_host_slug() {
  case "$1" in
    student-1) printf "student-one" ;;
    student-2) printf "student-two" ;;
    student-3) printf "student-three" ;;
    student-4) printf "student-four" ;;
    student-5) printf "student-five" ;;
    *) printf "%s" "$1" | sed -e 's/1/one/g' -e 's/2/two/g' -e 's/3/three/g' -e 's/4/four/g' -e 's/5/five/g' ;;
  esac
}

render_kind_config() {
  mkdir -p "$GENERATED_DIR"
  cat > "${GENERATED_DIR}/kind-cluster.yaml" <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: ${CLUSTER_NAME}
nodes:
  - role: control-plane
    image: ${KIND_NODE_IMAGE}
    extraPortMappings:
      - containerPort: ${HTTP_NODEPORT}
        hostPort: 80
        listenAddress: "${PUBLIC_HOST_IP}"
        protocol: TCP
      - containerPort: ${HTTPS_NODEPORT}
        hostPort: 443
        listenAddress: "${PUBLIC_HOST_IP}"
        protocol: TCP
  - role: worker
    image: ${KIND_NODE_IMAGE}
  - role: worker
    image: ${KIND_NODE_IMAGE}
EOF
}

ensure_cluster() {
  render_kind_config
  if kind get clusters | grep -qx "$CLUSTER_NAME"; then
    log "Deleting existing cluster ${CLUSTER_NAME}"
    kind delete cluster --name "$CLUSTER_NAME" >/dev/null
  fi
  log "Creating cluster ${CLUSTER_NAME}"
  kind create cluster --config "${GENERATED_DIR}/kind-cluster.yaml" --wait 180s >/dev/null
  kind export kubeconfig --name "$CLUSTER_NAME" >/dev/null
  kubectl config use-context "$KUBECONFIG_CONTEXT" >/dev/null
  kubectl wait --for=condition=Ready nodes --all --timeout=180s >/dev/null

  local nodes
  IFS=$'\n' read -r -d '' -a nodes < <(kubectl get nodes -o name | sed 's|node/||' && printf '\0')
  kubectl label node "${nodes[1]}" mlops.openai/compute=cpu --overwrite >/dev/null
  kubectl label node "${nodes[2]}" mlops.openai/compute=cpu mlops.openai/accelerator=nvidia mlops.openai/gpu-sim=true --overwrite >/dev/null
  kubectl label node "${nodes[1]}" mlops.openai/accelerator=amd mlops.openai/gpu-sim=true --overwrite >/dev/null
}

kind_subnet() {
  docker network inspect kind -f '{{range .IPAM.Config}}{{println .Subnet}}{{end}}' | awk '/^[0-9]+\./ {print; exit}'
}

calculate_metallb_range() {
  python3 - "$1" <<'PY'
import ipaddress
import sys

network = ipaddress.ip_network(sys.argv[1], strict=False)
end = ipaddress.ip_address(int(network.broadcast_address) - 6)
start = ipaddress.ip_address(int(end) - 49)
print(start, end)
PY
}

install_metallb() {
  helm repo add metallb https://metallb.github.io/metallb >/dev/null 2>&1 || true
  helm repo update >/dev/null
  kubectl create namespace metallb-system --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  log "Installing MetalLB ${METALLB_VERSION}"
  helm upgrade --install metallb metallb/metallb \
    --namespace metallb-system \
    --version "$METALLB_VERSION" \
    --wait >/dev/null

  local subnet pool_start pool_end
  subnet="$(kind_subnet)"
  read -r pool_start pool_end < <(calculate_metallb_range "$subnet")
  sed -e "s/__POOL_START__/${pool_start}/g" -e "s/__POOL_END__/${pool_end}/g" \
    "${ROOT_DIR}/manifests/metallb/ip-address-pool.template.yaml" > "${GENERATED_DIR}/metallb-pool.yaml"
  kubectl apply -f "${GENERATED_DIR}/metallb-pool.yaml" >/dev/null
  printf "METALLB_POOL_START=%s\nMETALLB_POOL_END=%s\n" "$pool_start" "$pool_end" > "${STATE_DIR}/metallb.env"
}

install_istio() {
  helm repo add istio https://istio-release.storage.googleapis.com/charts >/dev/null 2>&1 || true
  helm repo update >/dev/null
  kubectl create namespace istio-system --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  kubectl create namespace istio-ingress --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  log "Installing Istio base ${ISTIO_VERSION}"
  helm upgrade --install istio-base istio/base -n istio-system --version "$ISTIO_VERSION" --wait >/dev/null
  log "Installing Istio control plane"
  helm upgrade --install istiod istio/istiod -n istio-system --version "$ISTIO_VERSION" --wait >/dev/null
  log "Installing Istio ingress gateway"
  helm upgrade --install istio-ingressgateway istio/gateway -n istio-ingress --version "$ISTIO_VERSION" \
    --set service.type=LoadBalancer \
    --set service.ports[0].name=status-port \
    --set service.ports[0].port=15021 \
    --set service.ports[0].targetPort=15021 \
    --set service.ports[1].name=http2 \
    --set service.ports[1].port=80 \
    --set service.ports[1].targetPort=80 \
    --set service.ports[1].nodePort="${HTTP_NODEPORT}" \
    --set service.ports[2].name=https \
    --set service.ports[2].port=443 \
    --set service.ports[2].targetPort=443 \
    --set service.ports[2].nodePort="${HTTPS_NODEPORT}" \
    --wait >/dev/null
  wait_for_loadbalancer_ip istio-ingress istio-ingressgateway > "${INGRESS_LB_IP_FILE}"
}

install_katib() {
  kubectl create namespace kubeflow --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  log "Installing Katib ${KATIB_VERSION}"
  kubectl apply -k "github.com/kubeflow/katib.git/manifests/v1beta1/installs/katib-standalone?ref=${KATIB_VERSION}" >/dev/null
  kubectl rollout status deployment/katib-controller -n kubeflow --timeout=300s >/dev/null
  kubectl rollout status deployment/katib-db-manager -n kubeflow --timeout=300s >/dev/null
  kubectl rollout status deployment/katib-ui -n kubeflow --timeout=300s >/dev/null
  log "Pre-pulling Katib trial images"
  prepull_kind_image "docker.io/kubeflowkatib/file-metrics-collector:${KATIB_VERSION}"
  prepull_kind_image "docker.io/kubeflowkatib/suggestion-hyperopt:${KATIB_VERSION}"
}

install_minio() {
  ensure_secret_file "$MINIO_ROOT_USER_FILE" 12
  ensure_secret_file "$MINIO_ROOT_PASSWORD_FILE" 28
  helm repo add minio https://charts.min.io/ >/dev/null 2>&1 || true
  helm repo update >/dev/null
  kubectl create namespace "${PLATFORM_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  log "Installing MinIO ${MINIO_CHART_VERSION}"
  helm upgrade --install "${MINIO_RELEASE}" minio/minio \
    --namespace "${PLATFORM_NAMESPACE}" \
    --version "${MINIO_CHART_VERSION}" \
    --set mode=standalone \
    --set replicas=1 \
    --set persistence.size="${MINIO_STORAGE_SIZE}" \
    --set resources.requests.cpu=250m \
    --set resources.requests.memory=512Mi \
    --set resources.limits.cpu=1 \
    --set resources.limits.memory=2Gi \
    --set rootUser="$(<"${MINIO_ROOT_USER_FILE}")" \
    --set rootPassword="$(<"${MINIO_ROOT_PASSWORD_FILE}")" \
    --wait >/dev/null
  kubectl rollout status deployment/"${MINIO_RELEASE}" -n "${PLATFORM_NAMESPACE}" --timeout=300s >/dev/null
  kubectl -n "${PLATFORM_NAMESPACE}" create secret generic artifact-store-root \
    --from-literal=endpoint=http://minio.${PLATFORM_NAMESPACE}.svc.cluster.local:9000 \
    --from-literal=secure=false \
    --from-literal=accessKey="$(<"${MINIO_ROOT_USER_FILE}")" \
    --from-literal=secretKey="$(<"${MINIO_ROOT_PASSWORD_FILE}")" \
    --dry-run=client -o yaml | kubectl apply -f - >/dev/null
}

build_images() {
  log "Building project images"
  docker build -t "${WORKSPACE_IMAGE}" -f "${ROOT_DIR}/images/workspace/Dockerfile" "${ROOT_DIR}" >/dev/null
  docker build -t "${RUNTIME_IMAGE}" -f "${ROOT_DIR}/images/ml-runtime/Dockerfile" "${ROOT_DIR}" >/dev/null
  docker build -t "${PORTAL_IMAGE}" -f "${ROOT_DIR}/images/platform/Dockerfile" "${ROOT_DIR}" >/dev/null
  WORKSPACE_IMAGE_REVISION="$(docker image inspect "${WORKSPACE_IMAGE}" --format '{{.Id}}')"
  RUNTIME_IMAGE_REVISION="$(docker image inspect "${RUNTIME_IMAGE}" --format '{{.Id}}')"
  PORTAL_IMAGE_REVISION="$(docker image inspect "${PORTAL_IMAGE}" --format '{{.Id}}')"
  kind load docker-image "${WORKSPACE_IMAGE}" "${RUNTIME_IMAGE}" "${PORTAL_IMAGE}" --name "${CLUSTER_NAME}" >/dev/null
}

deploy_portal() {
  ensure_secret_file "$SESSION_SECRET_FILE" 32
  kubectl -n "${PLATFORM_NAMESPACE}" create secret generic portal-users \
    --from-file=users.yaml="${USERS_FILE}" \
    --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  cat > "${GENERATED_DIR}/portal.yaml" <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ${PORTAL_NAME}
  namespace: ${PLATFORM_NAMESPACE}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: ${PORTAL_NAME}-katib-reader
rules:
  - apiGroups: ["apps"]
    resources: ["deployments", "deployments/status"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["kubeflow.org"]
    resources: ["experiments", "trials"]
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: ${PORTAL_NAME}-katib-reader
subjects:
  - kind: ServiceAccount
    name: ${PORTAL_NAME}
    namespace: ${PLATFORM_NAMESPACE}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: ${PORTAL_NAME}-katib-reader
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${PORTAL_NAME}
  namespace: ${PLATFORM_NAMESPACE}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ${PORTAL_NAME}
  template:
    metadata:
      labels:
        app: ${PORTAL_NAME}
      annotations:
        mlops.openai/image-revision: ${PORTAL_IMAGE_REVISION}
    spec:
      serviceAccountName: ${PORTAL_NAME}
      containers:
        - name: portal
          image: ${PORTAL_IMAGE}
          imagePullPolicy: IfNotPresent
          env:
            - name: USERS_FILE
              value: /etc/mlops/users.yaml
            - name: SESSION_SECRET
              value: $(<"${SESSION_SECRET_FILE}")
            - name: OBJECT_STORAGE_ENDPOINT
              valueFrom:
                secretKeyRef:
                  name: artifact-store-root
                  key: endpoint
            - name: OBJECT_STORAGE_SECURE
              valueFrom:
                secretKeyRef:
                  name: artifact-store-root
                  key: secure
            - name: OBJECT_STORAGE_ACCESS_KEY
              valueFrom:
                secretKeyRef:
                  name: artifact-store-root
                  key: accessKey
            - name: OBJECT_STORAGE_SECRET_KEY
              valueFrom:
                secretKeyRef:
                  name: artifact-store-root
                  key: secretKey
            - name: KATIB_HOST
              value: katib.${PUBLIC_BASE_DOMAIN}
            - name: PUBLIC_BASE_DOMAIN
              value: ${PUBLIC_BASE_DOMAIN}
          ports:
            - name: http
              containerPort: 8000
          readinessProbe:
            httpGet:
              path: /healthz
              port: 8000
            initialDelaySeconds: 5
            periodSeconds: 5
          volumeMounts:
            - name: users
              mountPath: /etc/mlops
              readOnly: true
      volumes:
        - name: users
          secret:
            secretName: portal-users
---
apiVersion: v1
kind: Service
metadata:
  name: ${PORTAL_NAME}
  namespace: ${PLATFORM_NAMESPACE}
spec:
  selector:
    app: ${PORTAL_NAME}
  ports:
    - name: http
      port: 80
      targetPort: 8000
EOF
  kubectl apply -f "${GENERATED_DIR}/portal.yaml" >/dev/null
  kubectl rollout status deployment/"${PORTAL_NAME}" -n "${PLATFORM_NAMESPACE}" --timeout=300s >/dev/null
}

deploy_student() {
  local student="$1"
  local password
  password="$(workspace_token "$student")"
  cat > "${GENERATED_DIR}/${student}.yaml" <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: ${student}
  labels:
    katib.kubeflow.org/metrics-collector-injection: enabled
---
apiVersion: v1
kind: ResourceQuota
metadata:
  name: namespace-quota
  namespace: ${student}
spec:
  hard:
    requests.cpu: "6"
    requests.memory: 12Gi
    limits.cpu: "10"
    limits.memory: 20Gi
    requests.storage: 30Gi
    count/jobs.batch: "20"
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ${WORKSPACE_SERVICE_ACCOUNT}
  namespace: ${student}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: ${WORKSPACE_SERVICE_ACCOUNT}
  namespace: ${student}
rules:
  - apiGroups: [""]
    resources: ["pods", "pods/log", "configmaps", "secrets"]
    verbs: ["get", "list", "watch"]
  - apiGroups: [""]
    resources: ["services"]
    verbs: ["create", "delete", "get", "list", "patch", "update", "watch"]
  - apiGroups: ["apps"]
    resources: ["deployments"]
    verbs: ["create", "delete", "get", "list", "patch", "update", "watch"]
  - apiGroups: ["batch"]
    resources: ["jobs"]
    verbs: ["create", "delete", "get", "list", "patch", "watch"]
  - apiGroups: ["kubeflow.org"]
    resources: ["experiments", "trials", "suggestions"]
    verbs: ["create", "delete", "get", "list", "patch", "update", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: ${WORKSPACE_SERVICE_ACCOUNT}
  namespace: ${student}
subjects:
  - kind: ServiceAccount
    name: ${WORKSPACE_SERVICE_ACCOUNT}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: ${WORKSPACE_SERVICE_ACCOUNT}
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${WORKSPACE_PVC_NAME}
  namespace: ${student}
spec:
  accessModes: ["ReadWriteOnce"]
  resources:
    requests:
      storage: ${WORKSPACE_STORAGE_SIZE}
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: workspace
  namespace: ${student}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: workspace
  template:
    metadata:
      labels:
        app: workspace
        student: ${student}
      annotations:
        mlops.openai/image-revision: ${WORKSPACE_IMAGE_REVISION}
    spec:
      serviceAccountName: ${WORKSPACE_SERVICE_ACCOUNT}
      securityContext:
        fsGroup: 1000
      nodeSelector:
        mlops.openai/compute: cpu
      containers:
        - name: workspace
          image: ${WORKSPACE_IMAGE}
          imagePullPolicy: IfNotPresent
          env:
            - name: PASSWORD
              valueFrom:
                secretKeyRef:
                  name: workspace-auth
                  key: password
            - name: STUDENT_NAME
              value: ${student}
            - name: STUDENT_NAMESPACE
              value: ${student}
            - name: STUDENT_BUCKET
              value: ${student}
            - name: ARTIFACT_SECRET_NAME
              value: artifact-store
            - name: WORKSPACE_SERVICE_ACCOUNT
              value: ${WORKSPACE_SERVICE_ACCOUNT}
            - name: WORKSPACE_PVC_NAME
              value: ${WORKSPACE_PVC_NAME}
            - name: WORKSPACE_IMAGE
              value: ${WORKSPACE_IMAGE}
            - name: RUNTIME_IMAGE
              value: ${RUNTIME_IMAGE}
            - name: COMPUTE_MODE
              value: ${COMPUTE_MODE}
            - name: KATIB_HOST
              value: katib.${PUBLIC_BASE_DOMAIN}
            - name: INFERENCE_HOST
              value: api-$(student_host_slug "${student}").${PUBLIC_BASE_DOMAIN}
          ports:
            - name: http
              containerPort: 8080
          resources:
            requests:
              cpu: ${WORKSPACE_CPU_REQUEST}
              memory: ${WORKSPACE_MEMORY_REQUEST}
            limits:
              cpu: ${WORKSPACE_CPU_LIMIT}
              memory: ${WORKSPACE_MEMORY_LIMIT}
          readinessProbe:
            tcpSocket:
              port: 8080
            initialDelaySeconds: 10
            periodSeconds: 5
          volumeMounts:
            - name: workspace-home
              mountPath: /home/openvscode-server
      volumes:
        - name: workspace-home
          persistentVolumeClaim:
            claimName: ${WORKSPACE_PVC_NAME}
---
apiVersion: v1
kind: Service
metadata:
  name: workspace
  namespace: ${student}
spec:
  selector:
    app: workspace
  ports:
    - name: http
      port: 80
      targetPort: 8080
EOF
  kubectl apply -f "${GENERATED_DIR}/${student}.yaml" >/dev/null
  kubectl -n "${student}" create secret generic workspace-auth \
    --from-literal=password="${password}" \
    --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  kubectl -n "${student}" create secret generic artifact-store \
    --from-literal=endpoint=http://minio.${PLATFORM_NAMESPACE}.svc.cluster.local:9000 \
    --from-literal=secure=false \
    --from-literal=accessKey="$(<"${MINIO_ROOT_USER_FILE}")" \
    --from-literal=secretKey="$(<"${MINIO_ROOT_PASSWORD_FILE}")" \
    --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  kubectl rollout status deployment/workspace -n "${student}" --timeout=300s >/dev/null
}

deploy_students() {
  for student in "${STUDENTS[@]}"; do
    log "Deploying workspace for ${student}"
    deploy_student "$student"
  done
}

seed_datasets() {
  cat > "${GENERATED_DIR}/seed-job.yaml" <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: seed-datasets
  namespace: ${PLATFORM_NAMESPACE}
spec:
  backoffLimit: 0
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: seed
          image: ${PORTAL_IMAGE}
          imagePullPolicy: IfNotPresent
          env:
            - name: OBJECT_STORAGE_ENDPOINT
              valueFrom:
                secretKeyRef:
                  name: artifact-store-root
                  key: endpoint
            - name: OBJECT_STORAGE_SECURE
              valueFrom:
                secretKeyRef:
                  name: artifact-store-root
                  key: secure
            - name: OBJECT_STORAGE_ACCESS_KEY
              valueFrom:
                secretKeyRef:
                  name: artifact-store-root
                  key: accessKey
            - name: OBJECT_STORAGE_SECRET_KEY
              valueFrom:
                secretKeyRef:
                  name: artifact-store-root
                  key: secretKey
          command:
            - python
            - -c
            - |
              import csv
              import io
              import os
              import random
              import boto3
              from botocore.client import Config
              from botocore.exceptions import ClientError

              students = ["student-1","student-2"]
              client = boto3.client(
                  "s3",
                  endpoint_url=os.environ["OBJECT_STORAGE_ENDPOINT"],
                  aws_access_key_id=os.environ["OBJECT_STORAGE_ACCESS_KEY"],
                  aws_secret_access_key=os.environ["OBJECT_STORAGE_SECRET_KEY"],
                  region_name="us-east-1",
                  use_ssl=os.environ["OBJECT_STORAGE_SECURE"].lower() == "true",
                  config=Config(signature_version="s3v4", s3={"addressing_style": "path"}),
              )
              random.seed(42)
              stream = io.StringIO()
              writer = csv.writer(stream)
              writer.writerow(["overallqual","grlivarea","garagecars","totalbsmtsf","yearbuilt","saleprice"])
              for _ in range(220):
                  overallqual = random.randint(3, 10)
                  grlivarea = random.randint(900, 3200)
                  garagecars = random.randint(0, 4)
                  totalbsmtsf = random.randint(400, 2200)
                  yearbuilt = random.randint(1950, 2023)
                  saleprice = (
                      overallqual * 23000
                      + grlivarea * 78
                      + garagecars * 9500
                      + totalbsmtsf * 16
                      + (yearbuilt - 1950) * 750
                      + random.randint(-18000, 18000)
                  )
                  writer.writerow([overallqual, grlivarea, garagecars, totalbsmtsf, yearbuilt, saleprice])
              payload = stream.getvalue().encode("utf-8")
              for student in students:
                  try:
                      client.create_bucket(Bucket=student)
                  except ClientError:
                      pass
                  client.put_object(Bucket=student, Key="datasets/ames_housing_selected.csv", Body=payload, ContentType="text/csv")
EOF
  kubectl -n "${PLATFORM_NAMESPACE}" delete job seed-datasets --ignore-not-found >/dev/null
  kubectl apply -f "${GENERATED_DIR}/seed-job.yaml" >/dev/null
  kubectl wait --for=condition=complete job/seed-datasets -n "${PLATFORM_NAMESPACE}" --timeout=300s >/dev/null
}

deploy_routing() {
  kubectl -n "${PLATFORM_NAMESPACE}" apply -f "${ROOT_DIR}/manifests/istio/gateway.yaml" >/dev/null
  {
    cat <<EOF
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: platform-routing
  namespace: ${PLATFORM_NAMESPACE}
spec:
  hosts:
    - "portal.${PUBLIC_BASE_DOMAIN}"
    - "katib.${PUBLIC_BASE_DOMAIN}"
EOF
    for student in "${STUDENTS[@]}"; do
      local slug
      slug="$(student_host_slug "${student}")"
      cat <<EOF
    - "ws-${slug}.${PUBLIC_BASE_DOMAIN}"
    - "api-${slug}.${PUBLIC_BASE_DOMAIN}"
EOF
    done
    cat <<EOF
  gateways:
    - platform-gateway
  http:
    - match:
        - authority:
            exact: portal.${PUBLIC_BASE_DOMAIN}
      route:
        - destination:
            host: ${PORTAL_NAME}.${PLATFORM_NAMESPACE}.svc.cluster.local
            port:
              number: 80
    - match:
        - authority:
            exact: katib.${PUBLIC_BASE_DOMAIN}
          uri:
            exact: /
      rewrite:
        uri: /katib/
      route:
        - destination:
            host: katib-ui.kubeflow.svc.cluster.local
            port:
              number: 80
    - match:
        - authority:
            exact: katib.${PUBLIC_BASE_DOMAIN}
      route:
        - destination:
            host: katib-ui.kubeflow.svc.cluster.local
            port:
              number: 80
EOF
    for student in "${STUDENTS[@]}"; do
      local slug
      slug="$(student_host_slug "${student}")"
      cat <<EOF
    - match:
        - authority:
            exact: ws-${slug}.${PUBLIC_BASE_DOMAIN}
      route:
        - destination:
            host: workspace.${student}.svc.cluster.local
            port:
              number: 80
    - match:
        - authority:
            exact: api-${slug}.${PUBLIC_BASE_DOMAIN}
      route:
        - destination:
            host: ${student}-model-api.${student}.svc.cluster.local
            port:
              number: 80
EOF
    done
  } > "${GENERATED_DIR}/virtualservice.yaml"
  kubectl apply -f "${GENERATED_DIR}/virtualservice.yaml" >/dev/null
}

validate_stack() {
  log "Validating stack"
  wait_for_http_status "portal.${PUBLIC_BASE_DOMAIN}" "http://${PUBLIC_HOST_IP}/healthz" "200"
  wait_for_http_status "katib.${PUBLIC_BASE_DOMAIN}" "http://${PUBLIC_HOST_IP}/" "200"
  wait_for_http_status "ws-$(student_host_slug student-1).${PUBLIC_BASE_DOMAIN}" "http://${PUBLIC_HOST_IP}/" "200|302|401|403"
}

print_summary() {
  local ingress_lb_ip=""
  if [[ -f "${INGRESS_LB_IP_FILE}" ]]; then
    ingress_lb_ip="$(<"${INGRESS_LB_IP_FILE}")"
  fi
  cat <<EOF

Fresh private-cloud lab deployed.

Public host IP: ${PUBLIC_HOST_IP}
Base domain: ${PUBLIC_BASE_DOMAIN}
MetalLB ingress IP: ${ingress_lb_ip:-not-assigned}

Portal:
  http://portal.${PUBLIC_BASE_DOMAIN}

Katib:
  http://katib.${PUBLIC_BASE_DOMAIN}

Student workspaces:
EOF
  for student in "${STUDENTS[@]}"; do
    cat <<EOF
  ${student}:
    portal login username: ${student}
    portal password: $(student_password "${student}")
    workspace token: $(workspace_token "${student}")
    workspace: http://ws-$(student_host_slug "${student}").${PUBLIC_BASE_DOMAIN}
    inference api: http://api-$(student_host_slug "${student}").${PUBLIC_BASE_DOMAIN}
EOF
  done
  cat <<EOF

Admin:
  username: admin
  password: $(student_password admin)
EOF
}

main() {
  require_bin docker
  require_bin kind
  require_bin kubectl
  require_bin helm
  require_bin curl
  mkdir -p "$STATE_DIR" "$GENERATED_DIR"
  find "$GENERATED_DIR" -mindepth 1 -maxdepth 1 -type f -delete
  ensure_cluster
  install_metallb
  install_istio
  install_katib
  install_minio
  build_images
  deploy_portal
  deploy_students
  seed_datasets
  deploy_routing
  validate_stack
  print_summary
}

main "$@"
