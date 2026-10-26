# Open WebUI on its real data (NFS), talking to home_agent's in-cluster Service. CPU is Burstable on purpose.

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

        # secret_key_ref is read only at start, so a checksum forces a new Pod.
        annotations = {
          "checksum/oidc-client-secret" = sha256(kubernetes_secret_v1.open_webui_oidc_client_secret.data["OAUTH_CLIENT_SECRET"])
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
          # Hiding the form isn't enough: ENABLE_PASSWORD_AUTH=False switches password login off; no signups.
          env {
            name  = "ENABLE_LOGIN_FORM"
            value = "False"
          }
          env {
            name  = "ENABLE_PASSWORD_AUTH"
            value = "False"
          }
          env {
            name  = "ENABLE_SIGNUP"
            value = "False"
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
          # OAUTH_MERGE_ACCOUNTS_BY_EMAIL reuses any existing native
          env {
            name  = "ENABLE_OAUTH_SIGNUP"
            value = "True"
          }
          env {
            name  = "OAUTH_MERGE_ACCOUNTS_BY_EMAIL"
            value = "True"
          }
          env {
            name  = "OAUTH_PROVIDER_NAME"
            value = "Authelia"
          }
          env {
            name  = "OAUTH_CLIENT_ID"
            value = "open-webui"
          }
          env {
            name = "OAUTH_CLIENT_SECRET"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.open_webui_oidc_client_secret.metadata[0].name
                key  = "OAUTH_CLIENT_SECRET"
              }
            }
          }
          env {
            name  = "OPENID_PROVIDER_URL"
            value = "https://auth.jkandler.de/.well-known/openid-configuration"
          }
          env {
            name  = "OAUTH_SCOPES"
            value = "openid email profile groups"
          }
          env {
            name  = "OAUTH_CODE_CHALLENGE_METHOD"
            value = "S256"
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
          env {
            name  = "OPENAI_API_BASE_URL"
            value = "http://home-agent-svc/v1"
          }
          env {
            name  = "OPENAI_API_KEY"
            value = "home-agent-internal"
          }
          # Speech-to-text through home-agent (ADR 0012); local Whisper would need Hugging Face, which OFFLINE_MODE blocks.
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

          # No read_only_root_filesystem: Open WebUI writes outside its data dir.
          security_context {
            allow_privilege_escalation = false
            run_as_non_root            = true
            # UID 995, GID 0, matching the data directory's owner on the NFS export.
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

          # Up to 15 min to start, so a cold start from the HDD doesn't trip liveness into a restart loop.
          startup_probe {
            http_get {
              path = "/health"
              port = 8080
            }
            period_seconds    = 10
            timeout_seconds   = 5
            failure_threshold = 90
          }
          readiness_probe {
            http_get {
              path = "/health"
              port = 8080
            }
            period_seconds    = 30
            timeout_seconds   = 5
            failure_threshold = 5
          }
          liveness_probe {
            http_get {
              path = "/health"
              port = 8080
            }
            period_seconds    = 30
            timeout_seconds   = 5
            failure_threshold = 5
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
