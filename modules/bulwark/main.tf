# Bulwark Webmail (https://github.com/bulwarkmail/webmail, AGPL-3.0): a
# JMAP webmail client for Stalwart, giving mail, calendar, contacts and
# files in one UI. It runs in the browser against Stalwart's JMAP
# endpoint directly (stalwart.jkandler.de), so Stalwart needs CORS
# enabled for this app's origin (mail.jkandler.de) -- a manual Stalwart
# setting, not configurable from here.
#
# Version 1.10.0 (stable; 1.11.0 is still a beta), pinned by the
# multi-arch index digest like every other image here. A young,
# third-party project: revisit the pin deliberately, don't float it.
#
# Session secret: generated here and kept in Terraform state (S3,
# encrypted) rather than Secrets Manager, so this needs no change in
# aws/secrets-manager. Rotating it (taint random_id.session) logs every
# webmail user out.
#
# The image's user is the *name* `nextjs`, which Kubernetes can't verify
# as non-root, so a numeric UID is set explicitly. 1001 is that user's
# usual UID in Node images (not confirmed from the image itself) --
# if the Pod hits permission errors, check that first.

resource "random_id" "session" {
  byte_length = 32
}

resource "kubernetes_secret_v1" "bulwark_session" {
  metadata {
    name = "bulwark-session"
  }

  data = {
    SESSION_SECRET = random_id.session.b64_std
  }

  type = "Opaque"
}

# Authelia OIDC login ("sign in with Authelia" in Bulwark's own UI).
# This is separate from -- and does not by itself change -- the
# forward-auth gate already in front of mail.jkandler.de
# (modules/ingress' mail-chain): that gate gets you to Bulwark's own
# login screen at all; this is what Bulwark's login screen itself uses.
#
# Deliberately NOT wired yet: whether Bulwark actually uses the
# resulting OAuth access token to authenticate to Stalwart's JMAP
# endpoint (OAUTHBEARER), or still expects separate mailbox
# credentials, isn't confirmed -- and Stalwart's own directory is
# still "internal" (the wizard's choice), not OIDC, so it can't
# validate that token yet either. Until both sides are verified
# end-to-end, this only adds an OIDC login *option* to Bulwark; it does
# not complete single sign-on into the mailbox itself.
resource "kubernetes_secret_v1" "bulwark_oidc" {
  metadata {
    name = "bulwark-oidc"
  }

  data = {
    OAUTH_CLIENT_SECRET = var.bulwark_oidc_client_secret
  }

  type = "Opaque"
}

resource "kubernetes_deployment_v1" "bulwark" {
  metadata {
    name = "bulwark"
  }

  spec {
    replicas = 1

    # One RWO local-path volume: stop the old Pod before starting the new.
    strategy {
      type = "Recreate"
    }

    selector {
      match_labels = {
        app = "bulwark"
      }
    }

    template {
      metadata {
        labels = {
          app = "bulwark"
        }

        annotations = {
          "checksum/session" = sha256(random_id.session.b64_std)
          "checksum/oidc"    = sha256(jsonencode(kubernetes_secret_v1.bulwark_oidc.data))
        }
      }

      spec {
        automount_service_account_token = false

        security_context {
          fs_group = 1001
        }

        container {
          name  = "bulwark"
          image = "ghcr.io/bulwarkmail/webmail:1.10.0@sha256:f3b59980ccccb45e710f3e4e93cd5c1a66a6175fbf64493e0c86aa6f7fe6ac6b"

          port {
            name           = "http"
            container_port = 3000
          }

          env {
            name  = "JMAP_SERVER_URL"
            value = "https://stalwart.jkandler.de"
          }
          env {
            name  = "APP_NAME"
            value = "Mail"
          }
          env {
            name  = "SETTINGS_SYNC_ENABLED"
            value = "true"
          }
          env {
            name  = "SETTINGS_DATA_DIR"
            value = "/app/data/settings"
          }
          env {
            name = "SESSION_SECRET"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.bulwark_session.metadata[0].name
                key  = "SESSION_SECRET"
              }
            }
          }
          env {
            name  = "OAUTH_ENABLED"
            value = "true"
          }
          env {
            name  = "OAUTH_CLIENT_ID"
            value = "bulwark"
          }
          env {
            name  = "OAUTH_ISSUER_URL"
            value = "https://auth.jkandler.de"
          }
          # NOT set yet: Bulwark's own login form (username/password
          # against Stalwart directly) stays available alongside the
          # new "sign in with Authelia" button until the Stalwart-side
          # OIDC verification above is confirmed working end-to-end --
          # forcing it now, before that's confirmed, risks locking
          # every account out of a mail server that's now in real use.
          # env {
          #   name  = "AUTO_SSO_ENABLED"
          #   value = "true"
          # }
          env {
            name = "OAUTH_CLIENT_SECRET"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.bulwark_oidc.metadata[0].name
                key  = "OAUTH_CLIENT_SECRET"
              }
            }
          }

          resources {
            requests = {
              cpu    = "50m"
              memory = "192Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "512Mi"
            }
          }

          security_context {
            allow_privilege_escalation = false
            run_as_non_root            = true
            run_as_user                = 1001
            run_as_group               = 1001
            capabilities {
              drop = ["ALL"]
            }
          }

          volume_mount {
            name       = "data"
            mount_path = "/app/data"
          }

          # TCP probes on 3000, not an HTTP path: the app binds that
          # port unconditionally, and (lesson from modules/stalwart) a
          # probe that depends on unverified app behavior can restart a
          # healthy Pod in a loop.
          startup_probe {
            tcp_socket {
              port = 3000
            }
            period_seconds    = 5
            timeout_seconds   = 3
            failure_threshold = 30
          }
          readiness_probe {
            tcp_socket {
              port = 3000
            }
            period_seconds    = 30
            timeout_seconds   = 5
            failure_threshold = 3
          }
          liveness_probe {
            tcp_socket {
              port = 3000
            }
            period_seconds    = 30
            timeout_seconds   = 5
            failure_threshold = 5
          }
        }

        volume {
          name = "data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.bulwark.metadata[0].name
          }
        }
      }
    }
  }
}

# Port 80 like every other module's Service, so modules/ingress can
# reach it as bulwark-svc:80.
resource "kubernetes_service_v1" "bulwark" {
  metadata {
    name = "bulwark-svc"
  }

  spec {
    type = "ClusterIP"

    selector = {
      app = "bulwark"
    }

    port {
      name        = "http"
      port        = 80
      target_port = 3000
    }
  }
}
