{{/* Traefik's dynamic config: one router, service, and middleware chain per entry in .Values.routes. */}}
{{- define "ingress.routes" -}}
{{- $routers := dict -}}
{{- $services := dict -}}
{{- $middlewares := dict -}}
{{- range $name, $r := .Values.routes }}
  {{- $router := dict "entryPoints" (list "websecure") "tls" (dict "certResolver" "letsencrypt") "rule" $r.rule "service" $name "middlewares" (list (printf "%s-chain" $name)) }}
  {{- if hasKey $r "priority" }}{{ $_ := set $router "priority" (int64 $r.priority) }}{{ end }}
  {{- $_ := set $routers $name $router }}
  {{- $_ := set $services $name (dict "loadBalancer" (dict "passHostHeader" true "servers" (list (dict "url" $r.url)))) }}
  {{- $chain := list }}
  {{- if $r.ip_allow_list }}
    {{- $chain = append $chain (printf "%s-ip-allow-list" $name) }}
    {{- $_ := set $middlewares (printf "%s-ip-allow-list" $name) (dict "ipAllowList" (dict "sourceRange" $r.ip_allow_list)) }}
  {{- end }}
  {{- if $r.forward_auth }}{{ $chain = append $chain "authelia-forward-auth" }}{{ end }}
  {{- if $r.rate_limit }}
    {{- $chain = append $chain (printf "%s-rate-limit" $name) }}
    {{- $_ := set $middlewares (printf "%s-rate-limit" $name) (dict "rateLimit" (dict "average" (int64 $r.rate_limit.average) "period" "1m" "burst" (int64 $r.rate_limit.burst))) }}
  {{- end }}
  {{- if $r.max_body_bytes }}
    {{- $chain = append $chain (printf "%s-request-limit" $name) }}
    {{- $_ := set $middlewares (printf "%s-request-limit" $name) (dict "buffering" (dict "maxRequestBodyBytes" (int64 $r.max_body_bytes) "memRequestBodyBytes" (int64 $r.max_body_bytes))) }}
  {{- end }}
  {{- if $r.strip_prefix }}
    {{- $chain = append $chain (printf "%s-strip-prefix" $name) }}
    {{- $_ := set $middlewares (printf "%s-strip-prefix" $name) (dict "stripPrefix" (dict "prefixes" (list $r.strip_prefix))) }}
  {{- end }}
  {{- $chain = append $chain (printf "%s-security-headers" $name) }}
  {{- $headers := dict "contentTypeNosniff" true "frameDeny" (ternary $r.frame_deny true (hasKey $r "frame_deny")) "referrerPolicy" ($r.referrer_policy | default "no-referrer") "permissionsPolicy" "camera=(), microphone=(), geolocation=()" "stsSeconds" 31536000 "stsIncludeSubdomains" false }}
  {{- if $r.request_headers }}{{ $_ := set $headers "customRequestHeaders" $r.request_headers }}{{ end }}
  {{- $_ := set $middlewares (printf "%s-security-headers" $name) (dict "headers" $headers) }}
  {{- $_ := set $middlewares (printf "%s-chain" $name) (dict "chain" (dict "middlewares" $chain)) }}
{{- end }}
{{- $fixed := .Files.Get "files/fixed-routes.yml" | fromYaml }}
{{- toYaml (dict "http" (dict "routers" (merge $routers $fixed.routers) "services" (merge $services $fixed.services) "middlewares" (merge $middlewares $fixed.middlewares))) }}
{{- end -}}
