# Open WebUI itself -- the k3s-native copy of home-infra's own
# open_webui role, same pinned image, same real data (mounted from the
# NFS export in storage.tf, not started fresh -- see that file and
# home-infra's own nfs_server_exports comment for the live
# concurrent-write risk this depends on having already been handled:
# home-infra's own open-webui container must be stopped before this
# module is ever applied).
#
# No image_pull_secrets -- unlike home_agent, this is a public GHCR
# image.
#
# Points at home_agent's own in-cluster Service (modules/home_agent)
# instead of the Docker "home-agent" network alias -- everything else
# about the relationship (OpenAI-compatible API only, transcription
# endpoint reused for voice input, home-agent's own HOME_AGENT_MODEL/
# HOME_AGENT_STT_MODEL always winning over whatever this container
# claims) is unchanged from home-infra's own role.
#
# CPU sized differently from every other module here: requests (100m)
# and limits (500m) are deliberately split (Burstable, not this repo's
# usual limits-only-implies-Guaranteed) instead of just carrying over
# home-infra's own cpu_limit=1.0. That 1.0 is a Docker *ceiling* on a
# 4-core homeserver serving dozens of other containers, never a
# reservation -- copying it as a k3s Guaranteed *request* would repeat
# exactly the mistake home_agent's first cut made, and there isn't
# room for it: confirmed live via `kubectl describe node`, only 450m of
# the VM's 2 vCPU budget was free before this module. Real observed
# usage (`docker stats`) is 2.36% of one core idle -- 100m is already
# ~4x that, and 500m gives real burst room for actual chat load without
# threatening the node's schedulability the way a 1000m request would.

resource "kubernetes_deployment_v1" "open_webui" {
  metadata {
    name = "open-webui"
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "open-webui"
      }
    }

    template {
      metadata {
        labels = {
          app = "open-webui"
        }
      }

      spec {
        container {
          name  = "open-webui"
          image = "ghcr.io/open-webui/open-webui:v0.11.0-slim@sha256:88da9f0e08b8ada8e40bc6d6291494e2c6775a62d24b67b0cefb74ffee4ce621"

          port {
            name           = "http"
            container_port = 8080
          }

          env {
            name  = "HOME"
            value = "/app/backend/data/home"
          }
          env {
            name  = "WEBUI_SECRET_KEY_FILE"
            value = "/app/backend/data/.webui_secret_key"
          }
          env {
            name  = "WEBUI_NAME"
            value = "Home Agent"
          }
          env {
            name  = "WEBUI_URL"
            value = "https://ai.jkandler.de"
          }
          env {
            name  = "CORS_ALLOW_ORIGIN"
            value = "https://ai.jkandler.de"
          }
          env {
            name  = "WEBUI_AUTH"
            value = "True"
          }
          env {
            name  = "ENABLE_LOGIN_FORM"
            value = "True"
          }
          env {
            name  = "ENABLE_SIGNUP"
            value = "True"
          }
          env {
            name  = "DEFAULT_USER_ROLE"
            value = "pending"
          }
          env {
            name  = "ENABLE_PASSWORD_VALIDATION"
            value = "True"
          }
          env {
            name  = "PASSWORD_VALIDATION_REGEX_PATTERN"
            value = "^(?=.{12,72}$)(?=.*[a-z])(?=.*[A-Z])(?=.*\\d)(?=.*[^A-Za-z0-9]).*$"
          }
          env {
            name  = "PASSWORD_VALIDATION_HINT"
            value = "Use 12-72 characters with upper and lower case, a number, and a symbol."
          }
          env {
            name  = "WEBUI_SESSION_COOKIE_SECURE"
            value = "True"
          }
          env {
            name  = "WEBUI_AUTH_COOKIE_SECURE"
            value = "True"
          }
          env {
            name  = "WEBUI_SESSION_COOKIE_SAME_SITE"
            value = "strict"
          }
          env {
            name  = "WEBUI_AUTH_COOKIE_SAME_SITE"
            value = "strict"
          }
          env {
            name  = "ENABLE_OLLAMA_API"
            value = "False"
          }
          env {
            name  = "ENABLE_OPENAI_API"
            value = "True"
          }
          # home-agent's own in-cluster Service (modules/home_agent),
          # not the Docker "home-agent" network alias.
          env {
            name  = "OPENAI_API_BASE_URL"
            value = "http://home-agent-svc/v1"
          }
          env {
            name  = "OPENAI_API_KEY"
            value = "home-agent-internal"
          }
          # Route speech-to-text through home-agent (ADR 0012) instead of
          # the built-in local Whisper engine, which needs a Hugging Face
          # Hub download this container's OFFLINE_MODE (below)
          # deliberately blocks -- this sidesteps that restriction rather
          # than loosening it, since the openai STT engine never touches
          # HF Hub at all.
          env {
            name  = "AUDIO_STT_ENGINE"
            value = "openai"
          }
          env {
            name  = "AUDIO_STT_OPENAI_API_BASE_URL"
            value = "http://home-agent-svc/v1"
          }
          env {
            name  = "AUDIO_STT_OPENAI_API_KEY"
            value = "home-agent-internal"
          }
          env {
            name  = "AUDIO_STT_MODEL"
            value = "whisper-1"
          }
          env {
            name  = "OFFLINE_MODE"
            value = "True"
          }
          env {
            name  = "ENABLE_VERSION_UPDATE_CHECK"
            value = "False"
          }
          env {
            name  = "RAG_EMBEDDING_ENGINE"
            value = "openai"
          }
          env {
            name  = "RAG_OPENAI_API_BASE_URL"
            value = "http://home-agent-svc/v1"
          }
          env {
            name  = "RAG_OPENAI_API_KEY"
            value = "home-agent-internal"
          }
          env {
            name  = "BYPASS_EMBEDDING_AND_RETRIEVAL"
            value = "True"
          }
          env {
            name  = "RAG_EMBEDDING_MODEL_AUTO_UPDATE"
            value = "False"
          }
          env {
            name  = "RAG_RERANKING_MODEL_AUTO_UPDATE"
            value = "False"
          }
          env {
            name  = "DEFAULT_MODELS"
            value = "home-agent"
          }
          env {
            name  = "DEFAULT_PINNED_MODELS"
            value = "home-agent"
          }
          env {
            name  = "ENABLE_TITLE_GENERATION"
            value = "False"
          }
          env {
            name  = "ENABLE_TAGS_GENERATION"
            value = "False"
          }
          env {
            name  = "ENABLE_FOLLOW_UP_GENERATION"
            value = "False"
          }
          env {
            name  = "ENABLE_AUTOCOMPLETE_GENERATION"
            value = "False"
          }
          env {
            name  = "ENABLE_EVALUATION_ARENA_MODELS"
            value = "False"
          }
          env {
            name  = "ENABLE_MESSAGE_RATING"
            value = "False"
          }
          env {
            name  = "ENABLE_COMMUNITY_SHARING"
            value = "False"
          }
          env {
            name  = "ENABLE_API_KEYS"
            value = "False"
          }
          env {
            name  = "ENABLE_PLUGINS"
            value = "False"
          }
          env {
            name  = "ENABLE_PIP_INSTALL_FRONTMATTER_REQUIREMENTS"
            value = "False"
          }
          env {
            name  = "SAFE_MODE"
            value = "True"
          }
          env {
            name  = "ENABLE_CODE_EXECUTION"
            value = "False"
          }
          env {
            name  = "ENABLE_CODE_INTERPRETER"
            value = "False"
          }
          env {
            name  = "ENABLE_WEB_SEARCH"
            value = "False"
          }
          env {
            name  = "ENABLE_IMAGE_GENERATION"
            value = "False"
          }
          env {
            name  = "ENABLE_SUBAGENTS"
            value = "False"
          }
          env {
            name  = "USER_PERMISSIONS_CHAT_FILE_UPLOAD"
            value = "False"
          }
          env {
            name  = "USER_PERMISSIONS_CHAT_WEB_UPLOAD"
            value = "False"
          }
          env {
            name  = "USER_PERMISSIONS_CHAT_SYSTEM_PROMPT"
            value = "False"
          }
          env {
            name  = "USER_PERMISSIONS_WORKSPACE_MODELS_ACCESS"
            value = "False"
          }
          env {
            name  = "USER_PERMISSIONS_WORKSPACE_KNOWLEDGE_ACCESS"
            value = "False"
          }
          env {
            name  = "USER_PERMISSIONS_WORKSPACE_PROMPTS_ACCESS"
            value = "False"
          }
          env {
            name  = "USER_PERMISSIONS_WORKSPACE_TOOLS_ACCESS"
            value = "False"
          }
          env {
            name  = "USER_PERMISSIONS_WORKSPACE_SKILLS_ACCESS"
            value = "False"
          }
          env {
            name  = "AIOHTTP_CLIENT_ALLOW_REDIRECTS"
            value = "False"
          }
          env {
            name  = "SCARF_NO_ANALYTICS"
            value = "True"
          }
          env {
            name  = "DO_NOT_TRACK"
            value = "True"
          }
          env {
            name  = "ANONYMIZED_TELEMETRY"
            value = "False"
          }
          env {
            name  = "LOGURU_DIAGNOSE"
            value = "False"
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "512Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "1Gi"
            }
          }

          # Not read_only_root_filesystem, matching home-infra's own
          # role (read_only: false there too) -- Open WebUI writes
          # beyond just its mounted data dir, unlike home_agent/
          # nextcloud_tools.
          security_context {
            allow_privilege_escalation = false
            run_as_non_root            = true
            # UID 995, GID 0 -- not GID 988, the account's own default
            # group. home-infra's own docker_container task
            # deliberately starts this as "995:0" (root group), and the
            # real data directory on disk is owned 995:root mode 0750
            # to match. Getting this wrong would repeat the exact
            # Unix-socket GID mistake home_agent's first cut made, this
            # time against real, non-reproducible chat history over
            # NFS instead of an emptyDir.
            run_as_user  = 995
            run_as_group = 0
            capabilities {
              drop = ["ALL"]
            }
          }

          volume_mount {
            name       = "data"
            mount_path = "/app/backend/data"
          }

          # Mirrors home-infra's own Docker healthcheck (curl --fail
          # http://127.0.0.1:8080/health, 90s start_period for Open
          # WebUI's genuinely slow startup) as readiness/liveness
          # probes -- Kubernetes has no direct equivalent of Docker's
          # single healthcheck block, so both probes share timing that
          # matches that config as closely as the two models allow.
          readiness_probe {
            http_get {
              path = "/health"
              port = 8080
            }
            initial_delay_seconds = 90
            period_seconds        = 30
            timeout_seconds       = 5
            failure_threshold     = 5
          }
          liveness_probe {
            http_get {
              path = "/health"
              port = 8080
            }
            initial_delay_seconds = 90
            period_seconds        = 30
            timeout_seconds       = 5
            failure_threshold     = 5
          }
        }

        volume {
          name = "data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.open_webui_data.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "open_webui" {
  metadata {
    name = "open-webui-svc"
  }

  spec {
    selector = {
      app = "open-webui"
    }

    port {
      port        = 80
      target_port = 8080
    }
  }
}
