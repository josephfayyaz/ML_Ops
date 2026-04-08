FROM python:3.12-slim

ENV PIP_NO_CACHE_DIR=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir \
    --index-url https://download.pytorch.org/whl/cpu \
    torch==2.7.0 \
    torchvision==0.22.0 \
    torchaudio==2.7.0

COPY images/ml-runtime/requirements.txt /tmp/ml-runtime-requirements.txt
RUN pip install --no-cache-dir -r /tmp/ml-runtime-requirements.txt && rm -f /tmp/ml-runtime-requirements.txt

WORKDIR /workspace
