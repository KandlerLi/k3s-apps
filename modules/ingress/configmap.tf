# The "health" entryPoint is container-internal only -- never exposed
# via the LoadBalancer Service, just used by Kubernetes' own probes.
resource "kubernetes_config_map_v1" "ingress_static_config" {
  metadata {
    name = "ingress-static-config"
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

      # DNS-01, not TLS-ALPN-01 -- see current-state.md ("k3s learning
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

# Every backend routes to this cluster's own in-cluster Service DNS
# names directly. nextcloud is the one exception -- Nextcloud AIO's own
# Apache stays on the homeserver, reached through the
# nextcloud-aio-backend Service (nextcloud_backend.tf) instead.
resource "kubernetes_config_map_v1" "ingress_dynamic_config" {
  metadata {
    name = "ingress-dynamic-config"
  }

  data = {
    "routes.yml" = <<-EOT
      http:
        routers:
          nextcloud:
            rule: "Host(`nextcloud.jkandler.de`)"
            entryPoints:
              - websecure
            service: nextcloud
            middlewares:
              - nextcloud-chain
            tls:
              certResolver: letsencrypt
          home-agent-api:
            rule: >-
              Host(`ai.jkandler.de`)
              && (Path(`/healthz`) || Path(`/v1/chat`))
            priority: 100
            entryPoints:
              - websecure
            service: home-agent
            middlewares:
              - agent-chain
            tls:
              certResolver: letsencrypt
          open-webui:
            rule: "Host(`ai.jkandler.de`)"
            priority: 10
            entryPoints:
              - websecure
            service: open-webui
            middlewares:
              - open-webui-chain
            tls:
              certResolver: letsencrypt
          deluge:
            rule: "Host(`torrent.jkandler.de`)"
            entryPoints:
              - websecure
            service: deluge
            middlewares:
              - deluge-chain
            tls:
              certResolver: letsencrypt
          grafana:
            rule: "Host(`grafana.jkandler.de`)"
            entryPoints:
              - websecure
            service: grafana
            middlewares:
              - grafana-chain
            tls:
              certResolver: letsencrypt
          home:
            rule: "Host(`home.jkandler.de`)"
            entryPoints:
              - websecure
            service: home
            middlewares:
              - home-chain
            tls:
              certResolver: letsencrypt
          kubernetes-dashboard:
            rule: "Host(`k8s.jkandler.de`)"
            entryPoints:
              - websecure
            service: kubernetes-dashboard
            middlewares:
              - kubernetes-dashboard-chain
            tls:
              certResolver: letsencrypt
          apex-redirect:
            rule: "Host(`jkandler.de`)"
            entryPoints:
              - websecure
            service: noop@internal
            middlewares:
              - apex-redirect
            tls:
              certResolver: letsencrypt
          # authelia-chain is bypass -- Authelia's own access_control
          # already marks this hostname bypass (modules/authelia/
          # secret.tf), and the portal has to be reachable
          # unauthenticated or nobody could ever log in.
          auth:
            rule: "Host(`auth.jkandler.de`)"
            entryPoints:
              - websecure
            service: authelia
            middlewares:
              - authelia-chain
            tls:
              certResolver: letsencrypt
          # Bulwark webmail (modules/bulwark) at mail.jkandler.de, gated by
          # Authelia like every other UI here. It calls Stalwart's JMAP
          # endpoint straight from the browser (stalwart.jkandler.de,
          # below), so Stalwart needs CORS enabled for this origin.
          mail:
            rule: "Host(`mail.jkandler.de`)"
            entryPoints:
              - websecure
            service: mail
            middlewares:
              - mail-chain
            tls:
              certResolver: letsencrypt
          # Stalwart's protocol endpoints -- deliberately NOT behind
          # Authelia. JMAP calls from Bulwark's browser code, Thunderbird,
          # CalDAV/CardDAV and phone apps can't follow an Authelia login
          # redirect; every one of these paths has Stalwart's own
          # authentication (the same one its IMAP/SMTP ports use).
          stalwart-api:
            rule: >-
              Host(`stalwart.jkandler.de`)
              && (PathPrefix(`/jmap`) || PathPrefix(`/.well-known`)
              || PathPrefix(`/dav`) || PathPrefix(`/auth`)
              || PathPrefix(`/mail/config-v1.1.xml`)
              || PathPrefix(`/autodiscover`))
            priority: 100
            entryPoints:
              - websecure
            service: stalwart
            middlewares:
              - stalwart-api-chain
            tls:
              certResolver: letsencrypt
          # Everything else on stalwart.jkandler.de -- the /admin and
          # /account UIs and the management API they call -- is gated by
          # Authelia first, then Stalwart's own login.
          stalwart:
            rule: "Host(`stalwart.jkandler.de`)"
            priority: 10
            entryPoints:
              - websecure
            service: stalwart
            middlewares:
              - stalwart-chain
            tls:
              certResolver: letsencrypt

        services:
          nextcloud:
            loadBalancer:
              passHostHeader: true
              servers:
                - url: "http://nextcloud-aio-backend:11000"
          home-agent:
            loadBalancer:
              passHostHeader: true
              servers:
                - url: "http://home-agent-svc:80"
          open-webui:
            loadBalancer:
              passHostHeader: true
              servers:
                - url: "http://open-webui-svc:80"
          deluge:
            loadBalancer:
              passHostHeader: true
              servers:
                - url: "http://deluge-web-svc:80"
          grafana:
            loadBalancer:
              passHostHeader: true
              servers:
                - url: "http://grafana-svc:80"
          home:
            loadBalancer:
              passHostHeader: true
              servers:
                - url: "http://landing-page-svc:80"
          kubernetes-dashboard:
            loadBalancer:
              passHostHeader: true
              servers:
                - url: "http://kubernetes-dashboard-svc:80"
          authelia:
            loadBalancer:
              passHostHeader: true
              servers:
                - url: "http://authelia-svc:9091"
          mail:
            loadBalancer:
              passHostHeader: true
              servers:
                - url: "http://bulwark-svc:80"
          stalwart:
            loadBalancer:
              passHostHeader: true
              servers:
                - url: "http://stalwart-internal:8080"

        middlewares:
          nextcloud-secure-headers:
            headers:
              hostsProxyHeaders:
                - X-Forwarded-Host
              referrerPolicy: same-origin
              customRequestHeaders:
                X-Forwarded-Proto: https
          nextcloud-chain:
            chain:
              middlewares:
                - nextcloud-secure-headers
          # No Basic Auth fallback middleware exists anymore -- if
          # Authelia's SQLite storage loses data again (BACKLOG.md),
          # recovery is a ~5-minute drill (recreate db.sqlite3,
          # re-enroll TOTP if needed), not an instant middleware
          # rollback. See current-state.md's "k3s learning cluster"
          # entry for the full incident history. Response headers match
          # Authelia's own documented Traefik integration exactly.
          authelia-forward-auth:
            forwardAuth:
              address: "http://authelia-svc:9091/api/authz/forward-auth"
              trustForwardHeader: true
              authResponseHeaders:
                - Remote-User
                - Remote-Groups
                - Remote-Email
                - Remote-Name
          authelia-security-headers:
            headers:
              contentTypeNosniff: true
              frameDeny: true
              referrerPolicy: no-referrer
              permissionsPolicy: "camera=(), microphone=(), geolocation=()"
              stsSeconds: 31536000
              stsIncludeSubdomains: false
          authelia-chain:
            chain:
              middlewares:
                - authelia-security-headers
          agent-rate-limit:
            rateLimit:
              average: 10
              period: 1m
              burst: 5
          agent-request-limit:
            buffering:
              maxRequestBodyBytes: 16384
              memRequestBodyBytes: 16384
          agent-security-headers:
            headers:
              contentTypeNosniff: true
              frameDeny: true
              referrerPolicy: no-referrer
              permissionsPolicy: "camera=(), microphone=(), geolocation=()"
              stsSeconds: 31536000
              stsIncludeSubdomains: false
          agent-chain:
            chain:
              middlewares:
                - authelia-forward-auth
                - agent-rate-limit
                - agent-request-limit
                - agent-security-headers
          open-webui-rate-limit:
            rateLimit:
              average: 120
              period: 1m
              burst: 240
          open-webui-request-limit:
            buffering:
              maxRequestBodyBytes: 1048576
              memRequestBodyBytes: 1048576
          open-webui-chain:
            chain:
              middlewares:
                - open-webui-rate-limit
                - open-webui-request-limit
                - agent-security-headers
          # deluge-chain/grafana-chain/home-chain/kubernetes-dashboard-chain
          # are generated -- see generated-middlewares.yml below.
          # No request-size buffering middleware on the mail/stalwart
          # chains (unlike the others): JMAP/webmail uploads attachments.
          mail-rate-limit:
            rateLimit:
              average: 120
              period: 1m
              burst: 240
          mail-security-headers:
            headers:
              contentTypeNosniff: true
              frameDeny: true
              referrerPolicy: no-referrer
              permissionsPolicy: "camera=(), microphone=(), geolocation=()"
              stsSeconds: 31536000
              stsIncludeSubdomains: false
          mail-chain:
            chain:
              middlewares:
                - authelia-forward-auth
                - mail-rate-limit
                - mail-security-headers
          stalwart-chain:
            chain:
              middlewares:
                - authelia-forward-auth
                - mail-rate-limit
                - mail-security-headers
          # Higher ceiling than the UI chains: a JMAP client polls and
          # syncs constantly, and a phone app resyncing shouldn't trip it.
          stalwart-api-rate-limit:
            rateLimit:
              average: 600
              period: 1m
              burst: 1200
          stalwart-api-chain:
            chain:
              middlewares:
                - stalwart-api-rate-limit
                - mail-security-headers
          apex-redirect:
            redirectRegex:
              regex: '^https://jkandler\.de/(.*)'
              replacement: 'https://www.jkandler.de/$${1}'
              permanent: true
    EOT

    # Generated from locals below, not hand-written like routes.yml --
    # see decisions in docs/home-infra-ai-context's current-state.md
    # ("k3s learning cluster", 2026-09-22 entry) for why only these four
    # chains are generated and every other middleware stays hand-written.
    "generated-middlewares.yml" = yamlencode({
      http = {
        middlewares = local.generated_middlewares
      }
    })
  }
}

locals {
  authelia_gated_chains = {
    deluge                 = { rate = 120, burst = 240, buffer = 1048576 }
    grafana                = { rate = 120, burst = 240, buffer = 1048576 }
    "kubernetes-dashboard" = { rate = 120, burst = 240, buffer = 1048576 }
    home                   = { rate = 10, burst = 5, buffer = 16384 }
  }

  generated_middlewares = merge([
    for name, cfg in local.authelia_gated_chains : {
      "${name}-rate-limit" = {
        rateLimit = {
          average = cfg.rate
          period  = "1m"
          burst   = cfg.burst
        }
      }
      "${name}-request-limit" = {
        buffering = {
          maxRequestBodyBytes = cfg.buffer
          memRequestBodyBytes = cfg.buffer
        }
      }
      "${name}-security-headers" = {
        headers = {
          contentTypeNosniff   = true
          frameDeny            = true
          referrerPolicy       = "no-referrer"
          permissionsPolicy    = "camera=(), microphone=(), geolocation=()"
          stsSeconds           = 31536000
          stsIncludeSubdomains = false
        }
      }
      "${name}-chain" = {
        chain = {
          middlewares = [
            "authelia-forward-auth",
            "${name}-rate-limit",
            "${name}-request-limit",
            "${name}-security-headers",
          ]
        }
      }
    }
  ]...)
}
