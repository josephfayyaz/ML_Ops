#!/usr/bin/env bash

set -euo pipefail

HOME_DIR="${HOME:-/home/openvscode-server}"
PROJECT_DIR="${HOME_DIR}/project"
PLATFORM_DIR="${PROJECT_DIR}/.platform"
STARTER_DIR="/opt/mlops-starter"

mkdir -p "${PROJECT_DIR}" "${PLATFORM_DIR}"

mkdir -p "${HOME_DIR}/.kube"
cat > "${HOME_DIR}/.kube/config" <<EOF
apiVersion: v1
kind: Config
clusters:
  - name: in-cluster
    cluster:
      certificate-authority: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
      server: https://${KUBERNETES_SERVICE_HOST}:${KUBERNETES_SERVICE_PORT_HTTPS}
contexts:
  - name: workspace
    context:
      cluster: in-cluster
      namespace: ${STUDENT_NAMESPACE}
      user: workspace
current-context: workspace
users:
  - name: workspace
    user:
      tokenFile: /var/run/secrets/kubernetes.io/serviceaccount/token
EOF

render_templates() {
  export STUDENT_NAME
  export STUDENT_NAMESPACE
  export STUDENT_BUCKET
  export ARTIFACT_SECRET_NAME
  export WORKSPACE_SERVICE_ACCOUNT
  export WORKSPACE_PVC_NAME
  export RUNTIME_IMAGE
  export WORKSPACE_IMAGE
  export COMPUTE_MODE
  export INFERENCE_HOST
  export KATIB_HOST

  envsubst < "${STARTER_DIR}/project.yaml.template" > "${PROJECT_DIR}/project.yaml"
}

write_platform_config() {
  cat > "${PLATFORM_DIR}/platform.auto.yaml" <<EOF
student:
  name: ${STUDENT_NAME}
  namespace: ${STUDENT_NAMESPACE}
  bucket: ${STUDENT_BUCKET}
network:
  katib_host: ${KATIB_HOST}
  inference_host: ${INFERENCE_HOST}
object_storage:
  endpoint: http://minio.platform.svc.cluster.local:9000
  secure: false
  bucket: ${STUDENT_BUCKET}
artifacts:
  bucket: ${STUDENT_BUCKET}
  model_prefix: models
  evaluation_prefix: evaluations
kubernetes:
  namespace: ${STUDENT_NAMESPACE}
  workspace_pvc: ${WORKSPACE_PVC_NAME}
  service_account: ${WORKSPACE_SERVICE_ACCOUNT}
images:
  runtime: ${RUNTIME_IMAGE}
  workspace: ${WORKSPACE_IMAGE}
cluster:
  compute_mode: ${COMPUTE_MODE}
EOF
}

if [[ ! -f "${PLATFORM_DIR}/initialized" ]]; then
  cp -a "${STARTER_DIR}/." "${PROJECT_DIR}/"
  render_templates
  write_platform_config
  (
    cd "${PROJECT_DIR}"
    python -m student_lab.render_manifests --config "${PROJECT_DIR}/project.yaml"
  )
  touch "${PLATFORM_DIR}/initialized"
fi

exec "${OPENVSCODE_SERVER_ROOT}/bin/openvscode-server" \
  --host 0.0.0.0 \
  --port 8080 \
  --connection-token "${PASSWORD}" \
  --extensions-dir "${OPENVSCODE_EXTENSIONS_DIR:-/opt/openvscode-extensions}" \
  --telemetry-level off \
  "${PROJECT_DIR}"
