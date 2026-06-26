# 0005 -- Host hardening baseline

Status: **Accepted**

## Context

The VM is internet-reachable and runs unattended between sessions. It needs a
sensible hardening baseline -- but one matched to *this* threat model, not a generic
checklist. Under ADR 0001 there is no password login and no permanently open port,
which changes which defenses are worthwhile.

## Decision

- **Trusted Launch:** create the VM with `TrustedLaunch` security type -- secure
  boot + vTPM -- for boot-integrity guarantees.
- **Default-deny networking:** the NSG blocks inbound by default; SSH is opened only
  via Just-in-Time, only from the requester's source, for a bounded window (ADR 0001).
- **Automatic patching:** `unattended-upgrades` keeps the OS current without manual
  intervention between sessions.
- **Host firewall:** `ufw` as a second layer behind the NSG.
- **Drop `fail2ban`.** fail2ban primarily defends the **password** brute-force vector,
  which is **designed out** by certificate-only Entra login. Keeping it would add a
  moving part that guards an attack surface that does not exist here.

## Consequences

- Defenses are concentrated where this design is actually exposed (network exposure
  window, boot integrity, patch currency) rather than on a password vector that
  cannot be used.
- Fewer running services to maintain and reason about.
- If the access model ever changed to allow password auth, the fail2ban decision
  would need revisiting -- it is justified *only* by the cert-only login in ADR 0001.
