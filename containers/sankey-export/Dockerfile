FROM python:3.15-slim-trixie@sha256:65a65fc7b30b06cb6df4930fd4650697cb23f4c2698ab81fc87e4b031bc36928

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
