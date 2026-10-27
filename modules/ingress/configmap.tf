# The health entryPoint is for probes only, never exposed.
resource "kubernetes_config_map_v1" "ingress_static_config" {
  metadata {
    namespace = "apps"
    name      = "ingress-static-config"
  }

  data = {
    "traefik.yml" = <<-EOT
      global:
        checkNewVersion: false
        sendAnonymousUsage: false

      api:
        dashboard: false

      ping:
        entryPoint: health

      entryPoints:
        web:
          address: ":80"
          http:
            redirections:
              entryPoint:
                to: websecure
                scheme: https
                permanent: true
        websecure:
          address: ":443"
          transport:
            respondingTimeouts:
              readTimeout: 3610s
          http:
            encodedCharacters:
              allowEncodedSlash: true
              allowEncodedQuestionMark: true
              allowEncodedPercent: true
        health:
          address: "0.0.0.0:8082"

      providers:
        file:
          directory: /etc/traefik/dynamic
          watch: true

      # DNS-01, not TLS-ALPN-01 -- see history.md ("k3s learning
      # cluster") for why. Credentials come from dyndns's own
      # traefik-acme-dns01 IAM user (main.tf's container env).
      certificatesResolvers:
        letsencrypt:
          acme:
            email: "julian.kandler@outlook.com"
            storage: /letsencrypt/acme.json
            dnsChallenge:
              provider: route53
              delayBeforeCheck: 0

      log:
        level: INFO

      accessLog:
        format: json
        fields:
          headers:
            defaultMode: drop
    EOT
  }
}

# App routers come from each module's ingress_routes; only cross-cutting ones live here.
resource "kubernetes_config_map_v1" "ingress_dynamic_config" {
  metadata {
    namespace = "apps"
    name      = "ingress-dynamic-config"
  }

  data = {
    "routes.yml" = yamlencode({
      http = {
        routers     = local.routers
        services    = local.services
        middlewares = local.middlewares
      }
    })
  }
}

locals {
  router_defaults = {
    entryPoints = ["websecure"]
    tls         = { certResolver = "letsencrypt" }
  }

  app_routers = {
    for name, route in var.routes : name => merge(
      local.router_defaults,
      {
        rule        = route.rule
        service     = name
        middlewares = ["${name}-chain"]
      },
      route.priority == null ? {} : { priority = route.priority },
    )
  }

  routers = merge(local.app_routers, {
    nextcloud = merge(local.router_defaults, {
      rule        = "Host(`nextcloud.jkandler.de`)"
      service     = "nextcloud"
      middlewares = ["nextcloud-chain"]
    })
    apex-redirect = merge(local.router_defaults, {
      rule        = "Host(`jkandler.de`)"
      service     = "noop@internal"
      middlewares = ["apex-redirect"]
    })
  })

  services = merge(
    {
      for name, route in var.routes : name => {
        loadBalancer = { passHostHeader = true, servers = [{ url = route.url }] }
      }
    },
    {
      nextcloud = {
        loadBalancer = {
          passHostHeader = true
          servers        = [{ url = "http://${kubernetes_service_v1.nextcloud_aio_backend.metadata[0].name}:11000" }]
        }
      }
    },
  )

  app_middlewares = merge([
    for name, route in var.routes : merge(
      {
        "${name}-security-headers" = {
          headers = {
            contentTypeNosniff   = true
            frameDeny            = true
            referrerPolicy       = route.referrer_policy
            permissionsPolicy    = "camera=(), microphone=(), geolocation=()"
            stsSeconds           = 31536000
            stsIncludeSubdomains = false
          }
        }
        "${name}-chain" = {
          chain = {
            middlewares = concat(
              route.forward_auth ? ["authelia-forward-auth"] : [],
              route.rate_limit == null ? [] : ["${name}-rate-limit"],
              route.max_body_bytes == null ? [] : ["${name}-request-limit"],
              ["${name}-security-headers"],
            )
          }
        }
      },
      route.rate_limit == null ? {} : {
        "${name}-rate-limit" = {
          rateLimit = {
            average = route.rate_limit.average
            period  = "1m"
            burst   = route.rate_limit.burst
          }
        }
      },
      route.max_body_bytes == null ? {} : {
        "${name}-request-limit" = {
          buffering = {
            maxRequestBodyBytes = route.max_body_bytes
            memRequestBodyBytes = route.max_body_bytes
          }
        }
      },
    )
  ]...)

  middlewares = merge(local.app_middlewares, {
    nextcloud-secure-headers = {
      headers = {
        hostsProxyHeaders    = ["X-Forwarded-Host"]
        referrerPolicy       = "same-origin"
        customRequestHeaders = { X-Forwarded-Proto = "https" }
      }
    }
    nextcloud-chain = {
      chain = { middlewares = ["nextcloud-secure-headers"] }
    }
    # No Basic Auth fallback; headers as in Authelia's Traefik docs.
    authelia-forward-auth = {
      forwardAuth = {
        address             = "http://authelia-svc.auth.svc.cluster.local:9091/api/authz/forward-auth"
        trustForwardHeader  = true
        authResponseHeaders = ["Remote-User", "Remote-Groups", "Remote-Email", "Remote-Name"]
      }
    }
    apex-redirect = {
      redirectRegex = {
        regex       = "^https://jkandler\\.de/(.*)"
        replacement = "https://www.jkandler.de/$${1}"
        permanent   = true
      }
    }
  })
}
