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
          shared-auth:
            basicAuth:
              usersFile: /etc/traefik/users
              realm: Home Infrastructure
              removeHeader: true
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
                - shared-auth
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
          deluge-rate-limit:
            rateLimit:
              average: 120
              period: 1m
              burst: 240
          deluge-request-limit:
            buffering:
              maxRequestBodyBytes: 1048576
              memRequestBodyBytes: 1048576
          deluge-security-headers:
            headers:
              contentTypeNosniff: true
              frameDeny: true
              referrerPolicy: no-referrer
              permissionsPolicy: "camera=(), microphone=(), geolocation=()"
              stsSeconds: 31536000
              stsIncludeSubdomains: false
          deluge-chain:
            chain:
              middlewares:
                - shared-auth
                - deluge-rate-limit
                - deluge-request-limit
                - deluge-security-headers
          grafana-rate-limit:
            rateLimit:
              average: 120
              period: 1m
              burst: 240
          grafana-request-limit:
            buffering:
              maxRequestBodyBytes: 1048576
              memRequestBodyBytes: 1048576
          grafana-security-headers:
            headers:
              contentTypeNosniff: true
              frameDeny: true
              referrerPolicy: no-referrer
              permissionsPolicy: "camera=(), microphone=(), geolocation=()"
              stsSeconds: 31536000
              stsIncludeSubdomains: false
          grafana-chain:
            chain:
              middlewares:
                - shared-auth
                - grafana-rate-limit
                - grafana-request-limit
                - grafana-security-headers
          home-rate-limit:
            rateLimit:
              average: 10
              period: 1m
              burst: 5
          home-request-limit:
            buffering:
              maxRequestBodyBytes: 16384
              memRequestBodyBytes: 16384
          home-security-headers:
            headers:
              contentTypeNosniff: true
              frameDeny: true
              referrerPolicy: no-referrer
              permissionsPolicy: "camera=(), microphone=(), geolocation=()"
              stsSeconds: 31536000
              stsIncludeSubdomains: false
          home-chain:
            chain:
              middlewares:
                - shared-auth
                - home-rate-limit
                - home-request-limit
                - home-security-headers
          kubernetes-dashboard-rate-limit:
            rateLimit:
              average: 120
              period: 1m
              burst: 240
          kubernetes-dashboard-request-limit:
            buffering:
              maxRequestBodyBytes: 1048576
              memRequestBodyBytes: 1048576
          kubernetes-dashboard-security-headers:
            headers:
              contentTypeNosniff: true
              frameDeny: true
              referrerPolicy: no-referrer
              permissionsPolicy: "camera=(), microphone=(), geolocation=()"
              stsSeconds: 31536000
              stsIncludeSubdomains: false
          kubernetes-dashboard-chain:
            chain:
              middlewares:
                - shared-auth
                - kubernetes-dashboard-rate-limit
                - kubernetes-dashboard-request-limit
                - kubernetes-dashboard-security-headers
          apex-redirect:
            redirectRegex:
              regex: '^https://jkandler\.de/(.*)'
              replacement: 'https://www.jkandler.de/$${1}'
              permanent: true
    EOT
  }
}
