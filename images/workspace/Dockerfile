FROM gitpod/openvscode-server:latest

ARG KUBECTL_VERSION=v1.33.1

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    HOME=/home/openvscode-server \
    OPENVSCODE_EXTENSIONS_DIR=/opt/openvscode-extensions \
    VIRTUAL_ENV=/opt/venv \
    PATH=/opt/venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

USER root

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    build-essential \
    ca-certificates \
    curl \
    gettext-base \
    gpg \
    git \
    git-lfs \
    jq \
    less \
    openssh-client \
    procps \
    python3 \
    python3-pip \
    python3-venv \
    python-is-python3 \
    tini \
    unzip \
    xz-utils \
    && rm -rf /var/lib/apt/lists/*

RUN arch="$(dpkg --print-architecture)"; \
    curl -fsSL -o /usr/local/bin/kubectl "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${arch}/kubectl"; \
    chmod +x /usr/local/bin/kubectl; \
    curl -fsSL -o /usr/local/bin/mc "https://dl.min.io/client/mc/release/linux-${arch}/mc"; \
    chmod +x /usr/local/bin/mc

RUN python3 -m venv "${VIRTUAL_ENV}" && \
    "${VIRTUAL_ENV}/bin/pip" install --upgrade pip

RUN "${VIRTUAL_ENV}/bin/pip" install --no-cache-dir \
    --index-url https://download.pytorch.org/whl/cpu \
    torch==2.7.0 \
    torchvision==0.22.0 \
    torchaudio==2.7.0

COPY images/workspace/requirements.txt /tmp/workspace-requirements.txt
RUN "${VIRTUAL_ENV}/bin/pip" install --no-cache-dir -r /tmp/workspace-requirements.txt && rm -f /tmp/workspace-requirements.txt

COPY templates/student-workspace /opt/mlops-starter
COPY images/workspace/entrypoint.sh /usr/local/bin/workspace-entrypoint
RUN chmod +x /usr/local/bin/workspace-entrypoint && \
    mkdir -p "${OPENVSCODE_EXTENSIONS_DIR}" && \
    chown -R openvscode-server:openvscode-server /home/openvscode-server /opt/mlops-starter "${VIRTUAL_ENV}" "${OPENVSCODE_EXTENSIONS_DIR}"

USER openvscode-server
WORKDIR /home/openvscode-server

RUN "${OPENVSCODE_SERVER_ROOT}/bin/openvscode-server" --install-extension ms-python.python --extensions-dir "${OPENVSCODE_EXTENSIONS_DIR}" && \
    "${OPENVSCODE_SERVER_ROOT}/bin/openvscode-server" --install-extension ms-toolsai.jupyter --extensions-dir "${OPENVSCODE_EXTENSIONS_DIR}"

EXPOSE 8080

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/workspace-entrypoint"]
