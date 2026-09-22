# Static config -- mirrors home-infra's own shared_ingress role's
# templates/traefik.yml.j2 nearly verbatim. The "health" entryPoint
# stays container-internal only (never exposed via the LoadBalancer
# Service below, only reachable through Kubernetes' own readiness/
# liveness probes hitting the Pod's own IP directly) -- same shape as
# the original's own 127.0.0.1-bound health entryPoint, just via a
# Pod's own network namespace instead of the homeserver's loopback.
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

      # dnsChallenge, not tlsChallenge (the original shared_ingress role's
      # own choice) -- deliberately switched during this migration.
      # TLS-ALPN-01 always validates against the domain's real port 443,
      # so it ties cert issuance to the exact moment 80/443 get cut over
      # to k3s, with no way to rehearse it safely first. DNS-01 decouples
      # the two entirely: this Traefik can issue and renew real
      # production certs against jkandler.de's own Route53 zone at any
      # time, with no port ever touched -- proven and stable well before
      # the real DNAT cutover, not discovered live during it. Credentials
      # (lego's own route53 provider reads AWS_ACCESS_KEY_ID/
      # AWS_SECRET_ACCESS_KEY/AWS_HOSTED_ZONE_ID/AWS_REGION from the
      # environment, not from this file) come from dyndns's own
      # traefik-acme-dns01 IAM user -- see main.tf's container env.
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

# Dynamic config -- mirrors dynamic.yml.j2's own final, fully-enabled
# shape (every route home-infra's own shared_ingress had gated behind
# a per-service opt-in flag is unconditionally live in this repo
# already, confirmed by every one of those cutovers already being
# complete) with the Jinja conditionals resolved away, and every
# backend re-pointed at this cluster's own in-cluster Service DNS
# names directly (home-agent-svc, open-webui-svc, deluge-web-svc,
# grafana-svc, landing-page-svc -- all already exposing port 80,
# confirmed against each module's own Service) instead of bouncing
# back out through the node's own external address the way the old,
# outside-the-cluster homeserver Traefik had to. nextcloud is the one
# exception -- Nextcloud AIO's own Apache stays on the homeserver
# permanently, reached through the nextcloud-aio-backend Service
# (nextcloud_backend.tf) instead.
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
          # Stands the portal up at auth.jkandler.de -- added 2026-09-08
          # as a deliberately additive first step (see git history),
          # confirmed live with a real login + TOTP enrollment before
          # the cutover below ever happened. authelia-chain carries no
          # auth middleware of its own (bypass) -- Authelia's own
          # access_control already marks this exact hostname bypass
          # (modules/authelia/secret.tf), and the portal has to be
          # reachable unauthenticated or nobody could ever log in.
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
          # Re-cut over 2026-09-08 (same day as the original cutover
          # and its rollback -- see PARKED.md's own detailed writeup)
          # after real, deliberate load testing (sequential and
          # concurrent failed logins, a triggered regulation ban)
          # failed to reproduce the SQLite data-loss issue that
          # triggered the rollback -- treated as a real possible
          # one-time fluke rather than a confirmed recurring bug, not
          # worth continuing to block production auth on indefinitely.
          # If it recurs, the fix is the same known ~5-minute drill
          # (recreate db.sqlite3, possibly re-enroll TOTP) that resolved
          # it both times before -- see BACKLOG.md's own tracked item.
          # The shared-auth Basic Auth middleware that used to serve as
          # an instant one-line rollback for this was deliberately
          # retired 2026-09-11 (the underlying ingress/password Secrets
          # Manager keys were dead weight once every chain had actually
          # held stable on forward-auth for days) -- there is no
          # equivalent instant fallback any more; recovery is the
          # drill above or a slower rebuild of the old middleware from
          # git history. Response headers match Authelia's own documented Traefik
          # integration exactly (the four Remote-* headers its
          # forward-auth endpoint sends back once a request is
          # authenticated).
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
          # (and each one's own -rate-limit/-request-limit/-security-headers
          # trio) used to be hand-copied here, byte-identical except for the
          # name prefix and two numbers (rate/burst, buffer size) -- moved
          # 2026-09-22 (ponytail-audit) into generated-middlewares.yml
          # (below), a second file in this same ConfigMap that Traefik's
          # file provider merges in from the same watched directory
          # (providers.file.directory in configmap.tf's own static config).
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

    # Generated (see locals below), not hand-written like routes.yml above
    # -- these four chains were the one place this file had real,
    # mechanical duplication rather than four genuinely different routes.
    "generated-middlewares.yml" = yamlencode({
      http = {
        middlewares = local.generated_middlewares
      }
    })
  }
}

# The shared shape behind deluge-chain/grafana-chain/home-chain/
# kubernetes-dashboard-chain: an Authelia forward-auth gate, a per-service
# rate limit, a request-size limit, and a fixed set of security headers --
# differing only in the numeric rate/burst/buffer values. Every other
# chain in routes.yml's own middlewares (mail, stalwart, agent,
# open-webui, nextcloud, authelia) has its own distinct shape (some skip
# the request-limit, some skip forward-auth, some share a middleware
# across two routers) and stays hand-written there rather than being
# forced into this same generic shape for the sake of a single generic
# loop.
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
