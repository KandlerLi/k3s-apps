FROM python:3.13-slim-bookworm

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

# Kaleido drives a real Chromium-family browser via CDP to render the
# Sankey diagram -- same reasoning as home-infra's own Ansible role
# (see its tasks/main.yml), just baked into the image instead of
# apt-installed at Ansible-apply time, since a CronJob's Pod is
# ephemeral and can't afford to install packages on every run.
RUN apt-get update \
    && apt-get install --no-install-recommends -y chromium \
    && rm -rf /var/lib/apt/lists/*

# Points Kaleido's own driver (choreographer) at this exact binary
# instead of letting it try to download/manage its own private copy.
ENV BROWSER_PATH=/usr/bin/chromium

# choreographer/platformdirs still wants a real, writable $HOME for its
# own cache dir regardless of BROWSER_PATH -- confirmed live in
# home-infra#14 ("PermissionError: .../.local/share/choreographer/
# deps/chrome-linux64/chrome") once the Ansible-deployed copy ran under
# a locked-down systemd service account with no real home directory.
# The k3s Pod runs read_only_root_filesystem with a non-root UID (set
# in Terraform, not here) with the exact same shape, so this needs the
# identical fix from day one: HOME points at a path the Pod mounts
# read-write (an emptyDir at /tmp, see the CronJob's own volume_mount).
ENV HOME=/tmp

WORKDIR /app

COPY requirements.txt ./
RUN pip install --no-cache-dir --requirement requirements.txt

COPY finanzfluss_export.py ./

# Same fix as home_agent's own Dockerfile: COPY preserves the build
# context's file modes verbatim, which can come out non-world-readable
# from a fresh CI checkout -- and this container runs as a non-root UID
# set by the Pod's own security context, not root, so it needs to
# actually be able to read/execute what was just copied in.
RUN chmod -R a+rX /app

# Fixes trivy's DS-0002 -- matches the Pod's own security_context
# (modules/sankey_export/main.tf), which already forces this UID at
# runtime regardless of what the image defaults to. Adding it here too
# is real defense-in-depth, not redundant: it means the image is
# non-root even if run outside that specific Pod spec (e.g. a local
# `docker run` for debugging). Doesn't affect the CronJob's own
# init container, which deliberately runs as root (CAP_CHOWN only) to
# fix hostPath ownership -- Kubernetes' own runAsUser always overrides
# whatever USER an image sets, for any container using it.
USER 10010

# DS-0026 (no HEALTHCHECK) suppressed via .trivyignore, not inline --
# trivy can't inline-ignore a check triggered by an instruction's
# *absence*. A HEALTHCHECK has no meaning for a restart_policy: Never
# CronJob Pod that's expected to run once and exit every minute, not
# stay up as a long-running service.
CMD ["python", "finanzfluss_export.py"]
