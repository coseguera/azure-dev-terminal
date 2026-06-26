# 0004 -- A separable, platform-agnostic core build

Status: **Accepted**

## Context

An earlier experiment baked the dev environment (editor, toolchain, dotfiles)
directly into one host's cloud-init, and a second experiment **duplicated** that
same environment into its own cloud-init alongside Azure-specific concerns. The
result was two diverging copies of the "what makes it a dev box" logic, coupled to
platform details (Entra, JIT, admin accounts) that have nothing to do with the dev
environment itself.

## Decision

- Factor the dev environment into a **platform-agnostic `core-build/`**: one
  `install.sh` plus a `files/` tree that installs the toolchain and stages dotfiles
  into a **`--target-dir`** (default `/etc/skel`). It is deliberately **Azure-unaware**
  -- it knows nothing about Entra, cloud-init, JIT, or admin accounts -- and runs on
  any Debian/Ubuntu host (amd64 or arm64).
- Keep the Azure specifics in a **thin overlay**: the cloud-init `custom-data`
  inlines the entire `core-build/` tree (as a base64 tarball injected by
  `provision.sh`) and merely *invokes* `install.sh`, then layers on Azure-only
  steps.
- Target **`/etc/skel`** so the build is a **multi-user template**: each Entra user's
  home is seeded on first login via `pam_mkhomedir`, rather than provisioning a fixed
  dev account.

## Consequences

- A single source of truth for the dev environment, reusable unchanged on a laptop
  or Pi under a different overlay (a future `local-dev-machine` rewrite can consume
  it from this repo).
- The Azure layer stays thin and auditable; platform and environment concerns evolve
  independently.
- `install.sh` must be **idempotent and fail-loud** (each step self-guards; failure
  writes a sentinel and aborts) because it runs both interactively and unattended in
  cloud-init, where a silent failure would otherwise be masked by the boot's final
  "success" message.
- Inlining the tree as base64 means the rendered `custom-data` must stay **ASCII-only**
  and within size limits; see the gotchas doc.
