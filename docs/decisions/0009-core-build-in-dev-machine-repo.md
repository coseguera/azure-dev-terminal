# 0009 -- Core build lives in the `dev-machine` repo, consumed as a submodule

Status: **Accepted**

Supersedes the "lives in this repo" part of [ADR 0004](0004-separable-core-build.md);
the platform-agnostic principle there still holds.

## Context

ADR 0004 factored the dev environment into a platform-agnostic `core-build/` that
lived **inside** this repo, with the intent that other hosts (a Pi, a laptop) could
one day reuse it. That reuse is now concrete: the same core build needs to target a
Pi Zero 2 W (headless or local console) and an rpi4/rpi5 desktop, in addition to the
Azure SSH VM. Those hosts differ wildly in capability, so the build can no longer be
one fixed shape -- a Zero 2 W must skip Copilot CLI, Node, Mason language servers and
heavy Treesitter parsers, while a desktop adds i3 + a browser.

Keeping a single, growing, flag-driven installer as a subdirectory of one consumer
(`azure-dev-terminal`) would make the other consumers copy or fork it -- exactly the
duplication ADR 0004 set out to avoid.

## Decision

- The core build moves to its **own repository, `dev-machine`** (private), whose root
  is the installer: `install.sh` + `files/`. It stays host/cloud-unaware.
- The build **shape is selected by granular flags** (no profiles), documented in
  `dev-machine`'s own `install.sh --help`.
- `azure-dev-terminal` consumes it as a **git submodule** pinned at a commit, mounted
  at `core-build/`. `provision.sh` inlines the submodule payload (base64 tarball,
  excluding VCS metadata) exactly as before and invokes
  `install.sh --target-dir /etc/skel` with **no flags** -- so the Azure build is
  unchanged (full toolchain, no GUI).
- Host overlays own session-launch wiring (Pi tty1 autologin, or Azure
  provisioning). The installer only installs packages and stages config.

## Consequences

- A single source of truth for the dev environment across Azure and Pi hosts; each
  host pins the dev-machine commit it was validated against.
- Clones now need submodules: `git clone --recurse-submodules` (or
  `git submodule update --init`); `provision.sh` fails loud if `core-build/install.sh`
  is missing, pointing at the submodule init step.
- The submodule pin makes core-build upgrades explicit and reviewable (bump the
  pointer, re-validate), rather than silently drifting.
- The LazyVim "lite" flags (`--no-mason`, `--minimal-treesitter`) stage override Lua
  specs whose exact API must be validated against the LazyVim version actually cloned.
- Bumping the pin means reviewing the diff for changes to the no-flag path (packages
  always installed, `--target-dir` staging, exit behavior) -- the only path Azure
  exercises.
- Inlining still requires the rendered `custom-data` to stay **ASCII-only**; the
  submodule payload is verified ASCII-clean.
