# Copilot instructions for `azure-dev-terminal`

This repo provisions a **console-only, SSH-only** Azure dev VM (LazyVim + Copilot
CLI, no desktop/VNC), reached via Microsoft Entra ID SSH + Just-in-Time network
access. Read `docs/plan.md` for the full design and `docs/decisions/` for the why.

## Architecture in one screen

- **`core-build/`** -- a **git submodule** of the `dev-machine` repo: the
  platform-agnostic, flag-driven installer (`install.sh` + `files/`). Azure-
  unaware; installs the toolchain and stages dotfiles into `--target-dir` (default
  `/etc/skel`). Reusable on any Debian/Ubuntu host. Azure invokes it with no flags
  (full toolchain, no GUI). Run `git submodule update --init` after cloning.
  (ADR 0004, ADR 0009)
- **`cloud-init/azure/custom-data.example`** -- thin Azure overlay. Inlines the whole
  `core-build/` tree (base64) and invokes `install.sh`, then adds Azure-only steps.
- **`provision.sh`** -- assembly + access layer: renders `custom-data` (inlines
  core-build, injects admin), ASCII-guards it, then creates RG, default-deny NSG,
  TrustedLaunch VM, managed identity, AAD SSH extension, RBAC, Defender, JIT policy.
- **`lib/jit.{sh,ps1}`** -- shared JIT/CIDR logic used by both helpers. **Put shared
  access logic here**, not in the thin wrappers.
- **`connect.{sh,ps1}` / `sync.{sh,ps1}`** -- thin cross-platform wrappers over
  `lib/jit`. `connect` = `az ssh vm`; `sync` = rsync over the `az ssh config`
  transport.
- **`vm.lean.conf` / `vm.heavy.conf`** -- VM profiles (ADR 0003).

## Non-negotiable rules

1. **Keep committed content generic.** No location, timezone, lifestyle,
   or hardware/OS hints anywhere in git. Real source IPs, CIDRs, and host specifics
   live only in **gitignored** `*.local` / `connect.*.local` profiles and the
   rendered (gitignored) `custom-data`. Configs use generic values (e.g. `westus2`,
   UTC, `azureuser`).
2. **`custom-data` must be ASCII-only.** A non-ASCII byte breaks `az vm create`.
   Verify: `LC_ALL=C grep -nP '[^\x00-\x7F]' <file>` (no output = clean). No em-dashes
   or smart quotes in anything that ends up inlined.
3. **Cross-platform parity.** Any change to a `.sh` helper has a `.ps1` counterpart,
   and vice versa. Shared logic goes in `lib/jit.*`.
4. **`install.sh` is idempotent and fail-loud.** Every step self-guards so it can re-
   run; failures must surface (sentinel + non-zero exit), never be masked.
5. **Lint `az` invocations** against the installed CLI's `--help` before relying on a
   flag; CLI surfaces drift between versions.

## Conventions

- bash: `set -euo pipefail`; PowerShell: `Set-StrictMode` + `$ErrorActionPreference`.
- PowerShell: never name a parameter `$Profile` (it shadows the automatic `$PROFILE`);
  use `$NetworkProfile`.
- `core-build/` stays Azure-unaware -- no Entra/JIT/cloud-init knowledge leaks into it.
- New durable design choices get an ADR in `docs/decisions/`.

See `docs/gotchas.md` for the specific traps (apt lock race, multi-range NAT, ASCII, etc.).
