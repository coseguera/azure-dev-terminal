# azure-dev-terminal

Console-first, **SSH-only Azure dev VM** running **LazyVim + Copilot CLI** -- no
desktop environment, no VNC. A small, throwaway, reproducible cloud box whose UX is
just: open a stock terminal, connect, and land in LazyVim with Copilot CLI on
`Ctrl+/`. Works from **macOS, Linux, and Windows**.

The theme (Tokyo Night) and Nerd Font glyphs render in **your local terminal** over
SSH, so the VM installs nothing for display.

## Access model

- **Entra ID SSH only** -- connect with `az ssh vm` (short-lived certificate per
  session; MFA / Conditional Access / RBAC apply). No usable static key; the local
  account can't SSH in.
- **Port 22 closed by default** -- a Just-in-Time (JIT) policy opens it on demand to
  your current source, then auto-closes. No standing inbound rule.
- **Cross-platform** -- Azure CLI + ssh extension on macOS/Linux/Windows, with a `bash`
  and a PowerShell connection helper.

## Why an Azure VM (and why it's simpler than a Pi)

This distills a console-first dev environment down to a single shared **core build
layer** (LazyVim, Tokyo Night, Nerd Font expectations, system-wide Node via
NodeSource + the Copilot CLI, no system keyring) and runs it on an Azure VM reached
purely over SSH. Compared
with a physical Pi host, it drops all the physical-access machinery (USB gadget,
local console, Wi-Fi/regulatory, HDMI/KMS) and, compared with a desktop VM, it drops
VNC and the GUI layer entirely. What remains is reachability (network rules + source
restriction) and reproducibility (recreate from cloud-init custom-data).

## Status

Built and validated end-to-end on a live Azure VM (Entra ID SSH + JIT + cloud-init
core build). The full design and phased build plan live in
[`docs/plan.md`](docs/plan.md).

## Start here

- **Client setup (per OS):** [`docs/client-setup.md`](docs/client-setup.md)
- **LazyVim for VS Code users:** [`docs/lazyvim-for-vscode-users.md`](docs/lazyvim-for-vscode-users.md)
- **Plan & design:** [`docs/plan.md`](docs/plan.md)
- **Decisions (ADRs):** [`docs/decisions/`](docs/decisions/)
- **Gotchas:** [`docs/gotchas.md`](docs/gotchas.md)
- **Provisioning:** `provision.sh` + `cloud-init/` -- an Azure `--custom-data` config
  that reproduces the core build on first boot.

## Principles

- **Stock client.** Connect from any plain terminal (macOS/Linux/Windows) with a Nerd
  Font + truecolor; the VM is not customized for display.
- **Identity-based, on-demand access.** Entra ID SSH only; port 22 stays closed until
  JIT opens it.
- **Throwaway & reproducible.** "Reset" = delete/recreate the VM from custom-data.
- **ASCII-only custom-data.** Azure `--custom-data` must be pure ASCII (a non-ASCII
  byte breaks `az vm create`).
- **No secrets in git.** Source IPs/CIDRs, network profiles, keys, and filled configs
  stay local (see `.gitignore`).
