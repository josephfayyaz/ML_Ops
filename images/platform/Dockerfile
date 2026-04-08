FROM python:3.12-slim

ENV PIP_NO_CACHE_DIR=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY images/platform/requirements.txt /tmp/platform-requirements.txt
RUN pip install --no-cache-dir -r /tmp/platform-requirements.txt && rm -f /tmp/platform-requirements.txt

COPY apps/platform-portal/platform_portal /app/platform_portal

EXPOSE 8000

CMD ["uvicorn", "platform_portal.app:app", "--host", "0.0.0.0", "--port", "8000"]

