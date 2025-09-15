# Minimal, reusable Python container for static/simple apps
FROM python:3.12-slim AS base

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    HOST=0.0.0.0 \
    PORT=8000 \
    APP_ENTRY=tools/serve.py \
    APP_DIR=/app

# Create non-root user
RUN useradd -u 10001 -m appuser

WORKDIR ${APP_DIR}

# Install minimal runtime deps if needed (none by default)
# RUN apt-get update -y && apt-get install -y --no-install-recommends curl && rm -rf /var/lib/apt/lists/*

COPY . ${APP_DIR}

# Ensure scripts are executable
RUN chmod +x tools/entrypoint.sh || true

# Optional dependencies if a requirements.txt is present
RUN if [ -f requirements.txt ]; then pip install --no-cache-dir -r requirements.txt; fi

EXPOSE 8000

# Basic healthcheck hitting /healthz using Python to avoid extra deps
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD python -c "import os,urllib.request;url=f'http://127.0.0.1:{os.getenv(\"PORT\",\"8000\")}/healthz';urllib.request.urlopen(url).read() and print('ok')" || exit 1

USER appuser

ENTRYPOINT ["/bin/sh", "-c"]
CMD ["./tools/entrypoint.sh"]
