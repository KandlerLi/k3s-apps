variable "initial_signup" {
  description = <<-EOT
    true only while the first account is created: signups are open and
    every route, the client API included, sits behind Authelia. false
    closes signups and makes the client API public (ADR 0028), so open
    signups are never reachable without Authelia.
  EOT
  type        = bool
}
