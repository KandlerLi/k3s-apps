FROM python:3.13-slim-bookworm

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

# Kaleido renders the Sankey diagram through a real Chromium.
RUN apt-get update \
    && apt-get install --no-install-recommends -y chromium \
    && rm -rf /var/lib/apt/lists/*

# Kaleido's driver uses this binary instead of downloading its own.
ENV BROWSER_PATH=/usr/bin/chromium

# choreographer needs a writable $HOME for its cache.
ENV HOME=/tmp

WORKDIR /app

COPY requirements.txt ./
RUN pip install --no-cache-dir --requirement requirements.txt

COPY finanzfluss_export.py ./

# COPY keeps the checkout's file modes, which may not be world-readable for the non-root UID.
RUN chmod -R a+rX /app

# Matches the Pod's security_context (trivy DS-0002).
USER 10010

# No HEALTHCHECK for a run-once CronJob Pod; DS-0026 is ignored in .trivyignore.
CMD ["python", "finanzfluss_export.py"]
