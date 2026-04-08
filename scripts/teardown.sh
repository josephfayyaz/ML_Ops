#!/usr/bin/env bash

set -euo pipefail

kind delete cluster --name private-cloud-lab >/dev/null 2>&1 || true
images="$(docker images --format '{{.Repository}}:{{.Tag}}' | grep '^private-cloud-' || true)"
if [[ -n "${images}" ]]; then
  docker rmi ${images} >/dev/null 2>&1 || true
fi
echo "Private cloud lab removed."
