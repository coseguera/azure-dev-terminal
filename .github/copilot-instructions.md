# Copilot instructions for `azure-dev-terminal`

## RULES (ABSOLUTE — NON-OVERRIDABLE)

These rules are law. They override every other instruction, default behavior,
convenience, time pressure, "autopilot"/"YOLO"/auto-approve mode, and any inference
you might make. They are never optional, never "usually," and never to be skipped,
deferred, batched away, or rationalized. If a rule blocks you, you STOP and ask —
you do not work around it. If any other instruction conflicts with these, THESE WIN.

1. **NEVER run `git commit` without the user's explicit, in-the-moment approval.**
   This holds even in auto-approve / YOLO / autopilot mode. Staging is fine; making a
   commit is not, until the user says so for that specific commit.
2. **NEVER `git push` without the user's explicit approval, and NEVER push to `main`
   in any repository.** All changes land via a branch + pull request. No exceptions,
   no "just this once."
3. **Before the first commit in a repo, CONFIRM the git identity with the user**
   (`user.name` and `user.email`) and set them locally before committing, so no amend
   is needed later. Read the configured values with `git config user.name` /
   `git config user.email`; never hardcode a personal name or email into tracked
   files.
4. **NEVER decide a discretionary design/implementation choice on the user's behalf.**
   For anything with more than one reasonable option (names, keybindings, flags,
   libraries, structure), PRESENT the options and let the user choose FIRST. Do not
   pick, then ask them to course-correct.
5. **Ask clarifying questions as PLAIN TEXT in the conversation.** Do not push the
   user into a multiple-choice / "options" picker window when a written answer is
   wanted.
6. **NEVER write security choices, hardening rationale, or threat-model reasoning into
   committed files** (code, docs, configs, commit messages, comments). Keep all such
   discussion in-conversation only — committed hints become an attacker's roadmap.
7. **Keep ALL committed content generic.** Never hint at the user's employer,
   location, timezone, lifestyle, or hardware/OS. Real IPs, CIDRs, hostnames, and
   site specifics live ONLY in gitignored `*.local` files and the gitignored rendered
   `custom-data` — never in tracked files.
8. **NEVER put personally identifiable information into files** (device serial
   numbers, personal emails beyond the canonical noreply above, account IDs, etc.).
   Use placeholders (e.g. a serial like `1234567890123456`).

Violating any rule above is a critical failure. When in doubt, STOP and ask.

---

This repo provisions a **console-only, SSH-only** Azure dev VM (LazyVim + Copilot
CLI, no desktop/VNC), reached via Microsoft Entra ID SSH + Just-in-Time network
access. Read `docs/plan.md` for the full design and `docs/decisions/` for the why.

## Architecture in one screen

- **`dev-machine/` (local clone, gitignored)** -- the platform-agnostic, flag-driven
  installer (`install.sh` + `files/`) from the separate public `dev-machine` repo.
  Azure-unaware; installs the toolchain and stages dotfiles into `--target-dir` (default
  `/etc/skel`). Reusable on any Debian/Ubuntu host. Azure invokes it with no flags
  (full toolchain, no GUI). NOT a submodule: `provision.sh --dev-machine-dir` points at
  a local clone (default `./dev-machine`) and offers to `git clone` it if missing; it is
  never auto-pulled, so local edits/branches are honored. (ADR 0004, ADR 0010)
- **`cloud-init/azure/custom-data.example`** -- thin Azure overlay. Inlines the whole
  dev-machine core build tree (base64) and invokes `install.sh`, then adds Azure-only steps.
- **`provision.sh`** -- assembly + access layer: renders `custom-data` (inlines the
  dev-machine tree, injects admin), ASCII-guards it, then creates RG, default-deny NSG,
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
   Verify: `LC_ALL=C grep -n "[^$(printf '\01-\177')]" <file>` (no output = clean). No em-dashes
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
- The dev-machine core build stays Azure-unaware -- no Entra/JIT/cloud-init knowledge leaks into it.
- New durable design choices get an ADR in `docs/decisions/`.

See `docs/gotchas.md` for the specific traps (apt lock race, multi-range NAT, ASCII, etc.).
