# 0001 -- Access model: Entra ID SSH + Just-in-Time, no static keys

Status: **Accepted**

## Context

This is a single-user, console-only dev VM reachable over the public internet. The
two ways to expose SSH are: a static keypair with the port permanently open, or
identity-brokered access with the port closed by default. Static keys are long-lived
secrets that must be stored, rotated, and kept out of git; a permanently open port 22
is a continuous attack surface.

## Decision

- **Login is Microsoft Entra ID SSH.** A managed identity + the AAD SSH login VM
  extension + an RBAC role assignment let an authorized user obtain a **short-lived
  SSH certificate** per session (`az ssh vm`). There is no static keypair to store,
  distribute, or rotate.
- **The network is default-deny.** The NSG blocks inbound 22; a **Just-in-Time**
  policy opens it on demand, only from the requester's current source, for a bounded
  window, then it closes again.
- The connect/sync helpers automate: detect source -> request JIT -> issue cert ->
  connect. A per-network CIDR profile (gitignored) covers multi-range NAT egress.

## Consequences

- No SSH secret ever lives on disk or in git; access follows the user's Entra
  identity and can be revoked centrally.
- The port is open only during active use, shrinking the attack surface to bounded
  windows from a known source.
- Connecting requires the Azure CLI and an Entra login -- a deliberate trade of
  one-command convenience for a far smaller exposure. The helpers hide the steps.
- Source IP changes (switching networks) require re-detecting the source or selecting
  a covering CIDR profile; see ADR 0005 and the client-setup gotchas.
