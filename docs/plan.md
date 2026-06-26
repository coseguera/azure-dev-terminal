# Project plan: `azure-dev-terminal` -- console-first, SSH-only Azure dev VM

> Status: design + phased build plan. Seeded from a proposal that distills a
> console-first **LazyVim + Copilot CLI** environment (already built and
> hardware-validated on a Raspberry Pi in the sibling project
> [`local-dev-machine`](https://github.com/coseguera/local-dev-machine)) and re-targets
> it at an **Azure VM reached purely over SSH**. No desktop, no VNC. The client works
> on **macOS, Linux, and Windows**.

## 0. Current status

**Stage: complete -- second live run CONFIRMED full end-to-end.** All foundational
artifacts exist and have been validated across two live Azure VM runs (lean B2as_v2,
westus2).

**Run 1 (`core-build-foundation`):** `provision.sh` stood up the
RG/NSG/TrustedLaunch VM/Entra SSH ext/RBAC/Defender P2/JIT in ~4 min; JIT opened port 22
for a CIDR profile; Entra ID SSH login worked (sudo via RBAC); the core build installed
the full toolchain (nvim 0.12.3, node 22, Copilot CLI 1.0.65, lazygit 0.62.2,
+delta/fd/rg/fzf/jq/tmux), staged `/etc/skel`, a fresh user inherited the env, and
headless `Lazy! sync` installed 32 plugins. A dpkg-lock race bug was found and fixed
(commit d70acf5): `install.sh` now sets a global `DPkg::Lock::Timeout` and the overlay
runs the core build fail-loud (`core-build.status` sentinel + `CORE BUILD FAILED` marker).

**Run 2 (`docs/second-live-validation`):** cold re-provision confirmed the dpkg-lock race
fix end-to-end on a fresh boot. Full toolchain verified on the live VM:

| Check | Result |
|---|---|
| cloud-init | `done`, no errors |
| core-build sentinel | `OK` (`/var/lib/azure-dev-terminal/core-build.status`) |
| Build time | 128.45 s |
| nvim | 0.12.3 |
| node / npm | 22.23.1 / 10.9.8 |
| Copilot CLI | 1.0.65 (npm global) |
| gh | 2.95.0 |
| lazygit | 0.62.2 |
| delta / rg / fd / fzf / jq / tmux | all present |
| LazyVim plugins | 32 installed |
| `/etc/skel` staged | LazyVim config, tmux.conf, gitconfig, bashrc.d, lazygit theme |
| Entra user home | auto-created by `pam_aad.so` (AAD extension) from `/etc/skel` |
| ufw | active; deny-incoming default; allow 22/tcp (NSG is real gatekeeper) |
| unattended-upgrades | installed |
| SSH hardening | `PasswordAuthentication no`, `PermitRootLogin no` |
| azureuser lockout | password locked + empty `authorized_keys` -- cannot SSH |
| `.copilot/` token | present; headless auth confirmed (no keyring) |
| End-to-end UX | **Copilot CLI running inside the LazyVim terminal (`<C-/>`) on the live VM** |

**Note on `pam_mkhomedir`:** home directory creation for Entra users is handled by the
`pam_aad.so` module installed by the AAD SSH extension, not by an explicit
`pam_mkhomedir` PAM entry. This works correctly in practice; the comment in
`custom-data.example` that references `pam_mkhomedir` is a conceptual description, not a
literal PAM config.

**Next action:** project is feature-complete. Tear down the VM (billing). Any future
work is incremental improvement: additional OS validation for `feas-crossplatform`
(currently validated on one OS), adding a themed prompt (Starship/oh-my-posh) if desired,
or consuming `core-build/` from a future `local-dev-machine` rewrite.

## 1. Problem statement & goals

Run a console-first dev environment on a **throwaway, reproducible** Azure VM whose UX
is identical to `ssh`-ing into the Pi: connect from a stock client terminal and land
in LazyVim with Copilot CLI on `Ctrl+/`. Keep the operator's local machine pristine --
nothing is installed on it beyond the Azure CLI, a Nerd Font, and a truecolor terminal.
The client experience must be the same on **macOS, Linux, and Windows**.

The insight is that an Azure VM is the **simpler** target for this UX: most of a
physical host's complexity (USB gadget networking, local console, Wi-Fi/regulatory,
HDMI/KMS) exists only because the host is physical hardware. Over SSH, glyphs and theme
render in the **client** terminal, so the VM needs none of it. The cost is that we
inherit cloud **remote-access** concerns -- which we address with identity-based login
and on-demand network access rather than standing open ports.

### Success criteria

- From a stock terminal on macOS, Linux, **or** Windows: run the connection helper ->
  land on the VM -> `nvim` -> `<C-/>` -> Copilot CLI.
- Login is **Entra ID only** (ephemeral certificate); there is no usable static SSH key
  and the local admin account cannot SSH in.
- Port 22 is **closed by default** and opened only on demand (JIT) to the operator's
  current source, then auto-closes.
- Nerd Font glyphs + Tokyo Night colors render correctly (from the client terminal).
- The token vault unlocks headlessly (no graphical login session).
- The VM is fully reproducible from `--custom-data`; "reset" = delete + recreate.

## 2. Keep vs. drop -- the three-layer model

Think of each environment as three stacked layers. Only the **core build** is shared;
the access and GUI layers are host-specific and added or dropped per target.

| Layer | Pi (console/gadget) | Desktop dev VM | **azure-dev-terminal** |
|---|---|---|---|
| **Core build** | LazyVim, Tokyo Night, Nerd Fonts, Copilot CLI (nvm + Node), keyring vault, tmux, dotfiles | same idea (subset) | **keep -- fully portable** |
| **Access** | USB gadget / local console / Wi-Fi | Entra ID SSH + JIT, tunneled VNC | **keep Entra ID SSH + JIT; drop the tunnel** |
| **GUI** | none (console-first) | VNC + desktop | **drop VNC entirely** |

Thesis: *keep the top row, keep the identity-based SSH access, and drop both the
physical-access hacks and the VNC/desktop layer.* The access layer is the **same**
Entra ID SSH + JIT model a desktop dev VM uses, minus the VNC port-forward -- and
without the tunnel, the helper is plain `az ssh`, which is trivially cross-platform.

### Carries over (core build layer)

- **LazyVim** (idempotent clone) with the snacks `<C-/>` large-float terminal, plus a
  terminal-agnostic toggle fallback (`<C-t>` / `<leader>tt`) for clients that can't
  send `<C-/>`.
- **Tokyo Night** theme + **JetBrainsMono Nerd Font** glyph expectation (rendered
  client-side).
- **Copilot CLI** via **system-wide Node** (NodeSource), installed globally.
- **Terminal toolchain** -- `ripgrep`/`fd`/`fzf` (LazyVim deps) plus **git-delta** (git
  pager), **lazygit** (themed, `<leader>gg`), **gh** (GitHub CLI), and **Neovim from the
  latest GitHub release** (newer than apt; **fail loudly** if the download fails rather
  than silently installing a too-old apt nvim that breaks LazyVim).
- **Copilot CLI token storage** -- the agentic `@github/copilot` CLI persists its
  credentials in a **plain file under `~/.copilot`** (locked to the user), so **no system
  keyring is required**. The gnome-keyring / Secret Service / PAM stack is **dropped**
  (validate headless login on the first live VM, `feas-keyring`).
- **Host hardening** -- `unattended-upgrades` (auto security patches) + `ufw` (host
  firewall behind the NSG). `fail2ban` is intentionally **omitted** (it defends password
  brute-force, a vector designed out by cert-only Entra login).
- **Session persistence (tmux)** -- tmux installed with a minimal, Tokyo Night-aligned
  `.tmux.conf` (256color, mouse on, 50k history) and a `ta` reattach alias. **Opt-in,
  not auto-started on login.** Survives SSH connection loss (network blip, laptop sleep,
  closing the terminal) so work keeps running and can be reattached -- but **not** VM
  deallocation/recreate (see ephemerality, 3i). Does not integrate with the connect
  helpers and installs no plugin manager.
- **Dotfiles / profile** scaffolding staged into **`/etc/skel`** (copied into each Entra
  user's home on first login via `pam_mkhomedir`); no fixed dev account.

Mechanically these are cloud-init `write_files` + `runcmd` steps; the same cloud-init
engine runs on Azure, so most copy over directly.

### Gets dropped

- **Physical access layer:** USB gadget (CDC-ECM/libcomposite/`dwc2`), local console
  (cage + foot), Wi-Fi country/rfkill, HDMI/KMS, NetworkManager `usb0` drop-in.
- **GUI layer:** VNC server, desktop environment, the VNC port-forward, and all GUI
  session plumbing. (Dropping the tunnel is also what makes the client cross-platform --
  no OS-specific screen-sharing step.)

### Repo layout -- making the core build genuinely separable

The three-layer model is realized as a **layered repo structure** so the core build is a
standalone, platform-agnostic unit (not embedded in Azure cloud-init). This is what makes
it reusable later on an rpi4 / ARM box, per the separable-core-build intent.

```
core-build/                 # reusable, OS-aware (Debian/Ubuntu, multi-arch), Azure-UNAWARE
  install.sh                #   standalone + idempotent; TARGET-DIR param (default /etc/skel,
                            #   overridable to a real $HOME). Runnable by ANYTHING: cloud-init
                            #   runcmd, a manual SSH session, Ansible, etc. -- NOT cloud-init-dependent.
  files/                    #   .tmux.conf, .gitconfig, .bashrc.d/*.sh, lazygit theme, snacks.lua
cloud-init/
  azure/custom-data.example #   THIN Azure/Entra overlay: SSH hardening, ufw,
                            #   unattended-upgrades, pam_mkhomedir, __ADMIN__ lockdown,
                            #   then RUNS the core build (does not contain it)
  # (future) rpi4/user-data #   a second thin overlay for a Pi (NoCloud datasource)
provision.sh                # ASSEMBLES the final custom-data: inlines core-build/ into the
                            # azure overlay (same "assemble at provision time" idea as __ADMIN__)
```

Key principles:
- **`core-build/install.sh` knows nothing about Azure, Entra, cloud-init, or `__ADMIN__`.**
  Its only platform assumption is Debian/Ubuntu apt + multi-arch (amd64/arm64) release binaries.
- **Each platform is a thin cloud-init overlay** that does platform-specific setup, then
  invokes the same core build. cloud-init is the *common delivery format* (Azure
  `--custom-data`; rpi4 boot-partition `user-data`), but it is *one invoker*, not a dependency.
- **Assembly (inline-at-provision)** keeps the layers separate in-repo while still producing a
  **self-contained** custom-data with no boot-time repo/network coupling.

## 3. Phase 1 -- Feasibility (Azure-specific concerns)

Most of the build is known-good from the Pi; these are the things that genuinely change
on Azure and must be validated first.

### 3a. cloud-init datasource

The Pi uses **NoCloud** (files on the boot partition); Azure uses the **Azure
datasource** via `--custom-data`. Same engine and directives; build steps are reusable.
`bootcmd`/`runcmd` ordering assumptions should be re-checked but mostly hold.

### 3b. `--custom-data` must be pure ASCII

A non-ASCII byte (e.g. an em-dash) breaks `az vm create` with a `latin-1 codec can't
encode` error. Keep the merged config ASCII -- the same rule already enforced on the
Pi's config. Validate with `LC_ALL=C grep -nP '[^\x00-\x7F]' cloud-init/custom-data`.

### 3c. Access: Entra ID SSH (no static keys)

Login is **Microsoft Entra ID SSH**: install the AAD SSH login VM extension, give the
VM a **system-assigned managed identity**, and connect with `az ssh vm`, which issues a
short-lived certificate per session (so MFA / Conditional Access / RBAC all apply).
`az ssh` runs identically on macOS, Linux, and Windows. Design points to carry over:

- A throwaway SSH keypair is generated only to satisfy `az vm create` and is then
  **discarded** -- it is never a usable login path.
- The local admin account is locked out of SSH; the only credential that authenticates
  is the Entra-issued certificate.
- Grant the signed-in user admin (sudo) login via an RBAC role assignment.
- Do **not** rely on sshd `AllowGroups` for Entra users -- Entra ID SSH uses dynamic
  group membership that sshd's `AllowGroups` check does not see, so it would reject
  every legitimate login. Enforce Entra-only access via account lockdown instead.

### 3d. Network: default-deny NSG + Just-in-Time (JIT) access

Port 22 has **no standing allow rule**. The VM's NSG is default-deny inbound; a
**Just-in-Time** policy (Microsoft Defender for Servers) opens port 22 **on demand** to
the requester's current source for a bounded duration, then auto-closes. JIT requires
Defender for Servers (Plan 2) enabled on the subscription. A connection helper requests
JIT for the current session right before connecting.

### 3e. Source selection for JIT (networks behind a multi-range NAT pool)

By default JIT opens port 22 to the operator's detected public IP as a `/32` -- correct
for home/most networks, no config needed. But some networks route outbound traffic
through a **NAT pool**, so the IP that actually reaches Azure differs from a
"what's-my-IP" lookup and may span several ranges. A `/32` then never matches and SSH
times out. The fix is a **per-network profile** that overrides the JIT source with one
or more **covering CIDRs** (comma-separated):

- Profiles live in gitignored files (e.g. `connect.<name>.local`) so **no network
  details are ever committed**.
- The helper detects the public IP by default and uses the profile's CIDR list when a
  profile is selected.

### 3f. Cross-platform client (macOS, Linux, Windows)

Every client-side prerequisite is cross-platform, so support all three first-class:

- **Azure CLI + the `ssh` extension** run on macOS, Linux, and Windows.
- The connection helper is the only OS-specific surface. Since there is no VNC tunnel,
  it only needs to: detect/choose the JIT source, request JIT, optionally start the VM,
  then `az ssh vm`. Ship two thin equivalents that do the same steps:
  - a POSIX **`bash`** helper (`connect.sh`) for macOS/Linux, and
  - a **PowerShell** helper (`connect.ps1`) for Windows (also usable via PowerShell on
    macOS/Linux).
- Public-IP detection and JSON building must avoid OS-specific tools; prefer the Azure
  CLI and portable primitives. Per-network CIDR profiles are shared plain key/value
  files both helpers can read.
- Document the native terminal options per OS in the client guide (see 3g).

### 3g. Glyphs & theme are a client concern

Nothing to install on the VM for rendering. Ensure the *operator's* terminal has the
Nerd Font + truecolor; document client setup per OS rather than provisioning it on the
VM:

- **macOS:** a truecolor terminal (e.g. iTerm2/Ghostty or the stock Terminal) + a
  Homebrew-installed Nerd Font.
- **Linux:** most modern terminals are truecolor; install a Nerd Font via the package
  manager or font files.
- **Windows:** Windows Terminal (truecolor, supports Nerd Fonts) + an installed Nerd
  Font; connect from PowerShell.

### 3h. Copilot CLI token storage (no keyring)

The agentic `@github/copilot` CLI stores its credentials in a **plain file under
`~/.copilot`** (locked to the user), and works headless without a Secret Service. So the
gnome-keyring / `libpam-gnome-keyring` / D-Bus / PAM stack is **dropped entirely** -- a
significant simplification (5 fewer packages + no PAM edits + no empty-password caveat).
Still validate headless `copilot` login persists across sessions on the first live VM
(`feas-keyring`); if a future CLI version regresses to requiring Secret Service, reintroduce
the keyring overlay then.

### 3i. Ephemerality model

"Throwaway" = **deallocate or delete** the VM and recreate from `--custom-data`. The
connection helper starts the VM (with the operator's own credentials) when it is
deallocated; `stop` deallocates it manually to save cost. Because the chosen baseline
runs **always-on under budget** (see 3j, no guest-side auto-shutdown), the VM never
needs to stop *itself* -- so the **VM self-deallocate managed-identity role is dropped**.
The reproducibility guarantee matches the Pi's reflash; only the reset mechanism differs.

### 3j. VM baseline (resolved)

**Decision: `Standard_B2as_v2`** (burstable, 2 vCPU / 8 GB) with a **64 GB Standard SSD
(E6)** OS disk, Ubuntu LTS. All-in **~$87/mo running 24/7** (VM ~$62 + disk ~$4.80 +
Defender for Servers P2 ~$15 + Standard public IP ~$3.7), comfortably under the
**~$150/month budget** -- so the VM is **always-on, no auto-shutdown** (see 3k).

Burstable suits the workload: terminal Copilot CLI + LazyVim is near-idle most of the
time (banking CPU credits) with short bursts (LSP indexing, builds, `:Lazy! sync`).
The Pi's sluggishness was SD-card I/O + ARM, not CPU/RAM, so a small x86 VM with SSD
feels snappy. Keep the **lean/heavy two-profile pattern**: lean is the default above; a
heavy dedicated D-series is available for sustained heavy compiles (see 3k for the
cost/auto-shutdown coupling).

### 3k. Sizing x burstability x auto-shutdown

The VM uses **Trusted Launch** (Secure Boot + vTPM + measured boot) for boot integrity.
Cost control is governed by one coupled rule:

- Burstable VMs **bank CPU credits while idle** and **reset them on deallocate**. Running
  always-on continuously banks credits (full balance ready to burst) **and** fits budget
  -- so burstable + always-on reinforce each other. **No auto-shutdown** for the lean
  baseline.
- The trigger to leave burstable is **sustained high-CPU work** that exhausts credits and
  throttles to baseline -- which points to a **dedicated D-series**.
- A dedicated 4-core (e.g. `D4as_v5`, ~$151/mo at 24/7) **breaks the $150 budget if
  always-on**, so a heavy profile must ship **with guest-side auto-shutdown** to claw the
  cost back (dedicated SKUs have no burst credits to lose, so no penalty).
- **Rule:** *Burstable -> always-on. Dedicated (sustained loads) -> auto-shutdown.*

## 4. Phase 2 -- Build plan

1. **Skeleton** -- repo scaffold (README, `docs/`, `.gitignore` for secret overlays and
   network profiles).
2. **Core build (`core-build/`)** -- a **standalone, Azure-unaware** `install.sh`
   (idempotent, multi-arch, **target-dir param**) + `files/`: toolchain (incl.
   **git-delta, lazygit (themed), gh, Neovim-from-release with fail-loud download**),
   **system-wide Node + Copilot CLI**, LazyVim config staged (plugins install on first
   `nvim`), Tokyo Night, tmux + minimal `.tmux.conf` + `ta` alias, lazygit theme,
   `.gitconfig` (delta pager), `.bashrc.d` PATH/aliases. **No keyring stack** (Copilot
   uses its `~/.copilot` file token). Runnable by any invoker, not just cloud-init.
3. **Azure cloud-init overlay (`cloud-init/azure/custom-data.example`)** -- a **thin**
   ASCII-only overlay: SSH hardening, **`unattended-upgrades` + `ufw`**, `pam_mkhomedir`,
   `__ADMIN__` lockdown, then **runs the core build** (inlined at provision time). It does
   not contain the toolchain logic.
3. **Provisioning script** -- create RG, default-deny NSG, VM with **Trusted Launch**
   (Secure Boot + vTPM) + managed identity + AAD SSH login extension, RBAC for admin
   login, enable Defender for Servers, and create the per-VM JIT policy for port 22.
   (No self-deallocate role -- the lean baseline is always-on.) Also **assembles** the
   final `custom-data` by inlining `core-build/` into the Azure overlay.
4. **Connection helpers (cross-platform)** -- a `bash` `connect.sh` (macOS/Linux) and a
   PowerShell `connect.ps1` (Windows): start-if-deallocated, request JIT for the current
   source or a selected per-network CIDR profile, then `az ssh vm` straight into a shell
   (no VNC port-forward). Both read the same gitignored profile files.
5. **File-sync helper (cross-platform)** -- redesigned from the experiment's `sync.sh`:
   rsync push/pull over the Entra SSH connection, supporting **both files and
   directories**, reusing **shared JIT/CIDR logic** (no duplication with connect), with
   bash + PowerShell parity. Synced files owned by the dev user.
6. **Token-storage validation** -- confirm `copilot` login persists across SSH sessions
   headless (file token under `~/.copilot`), with no keyring.
7. **Client setup doc (per OS)** -- Azure CLI + ssh extension, Nerd Font + truecolor
   terminal for macOS/Linux/Windows, the `<C-/>` / fallback toggle note (no VM-side
   rendering), and a **session persistence (tmux)** note: reattach with `ta` after a
   dropped connection; survives disconnects but not VM deallocation/recreate.
8. **ADRs + agent docs** -- a fresh `docs/decisions/` (one ADR per key decision) plus a
   generic `.github/copilot-instructions.md` and a gotchas doc, all **kept generic** with
   no personal or environment-specific context.
9. **Ephemerality** -- document delete/recreate as the reset path; ensure the
   provisioner is idempotent.

## 5. Open questions to resolve during Phase 1

- **Sharing the core build across hosts (resolved).** This repo is **self-contained**
  now, but is designed so the **core build is a cleanly separable layer**, isolated from
  the Azure access/provisioning code. Intent: this repo becomes the **canonical source**
  of the core build, which a future `local-dev-machine` rewrite can consume from here
  (submodule / include / copy) without dragging Azure bits along.
- **VM baseline (resolved).** `Standard_B2as_v2`, 64 GB Standard SSD, Ubuntu LTS,
  always-on (~$87/mo, under the $150 budget). Lean/heavy two-profile pattern kept; the
  heavy dedicated profile pairs with auto-shutdown (see 3k).
- **JIT duration & policy.** Session length (within policy max) and whether to script
  re-requests for long sessions.
- **Helper parity.** How to keep the `bash` and PowerShell helpers behaviorally
  identical (shared profile format; same JIT/`az ssh` steps) without duplicating logic
  that drifts.
- **First validation.** Stand up the VM with the core-build `--custom-data`; connect via
  Entra ID SSH with a JIT-opened port 22 from each OS; confirm LazyVim + Copilot CLI +
  headless vault, and glyphs/theme from the client terminal.

## 6. Notes / guardrails

- **No secrets in git.** Source IPs/CIDRs, network profiles, keys, and filled configs
  stay local.
- **Fully generic content.** Nothing committed reveals personal or environment-specific
  context; keep docs, code, and configs generic. Environment specifics (source ranges,
  network profiles) live only in gitignored overlays, never in committed text.
- **Budget ~$150/month.** The lean baseline runs always-on under budget; bigger
  dedicated profiles must pair with auto-shutdown (see 3k).
- **Concept over copy.** The two sibling repos are experiments; bring concepts here and
  **redesign** cleanly rather than copying implementations.
- **ASCII-only `--custom-data`.** Enforced (see 3b).
- **Identity-based, on-demand access.** Entra ID SSH only; port 22 closed until JIT
  opens it; no standing inbound rule.
- **Boot integrity.** VM uses Trusted Launch (Secure Boot + vTPM).
- **Cross-platform client.** macOS, Linux, and Windows are all first-class; keep the
  helpers and client docs in sync across them.
- **Client renders display.** The VM installs nothing for glyphs/theme.
- **Reproducible & throwaway.** Always recreatable from `--custom-data`.

## 7. Todo checklist

### Phase 1 -- Feasibility (do these first; few hard inter-deps)

- [x] **feas-customdata** -- Port a minimal core build to Azure `--custom-data`; confirm
      cloud-init runs to completion on the Azure datasource.
- [x] **feas-ascii** -- Enforce/verify pure-ASCII custom-data in the build pipeline.
- [x] **feas-access** -- Validate Entra ID SSH (AAD login extension + managed identity +
      RBAC) end to end; confirm the local account cannot SSH and no static key works.
- [x] **feas-jit** -- Confirm default-deny NSG + JIT opens port 22 on demand and
      auto-closes (Defender for Servers Plan 2 enabled).
- [x] **feas-source** -- Confirm `/32` default and per-network CIDR profile both work
      (incl. a NAT-pool network); keep all CIDRs gitignored.
- [ ] **feas-crossplatform** -- Confirm the connect flow works from macOS, Linux, and
      Windows (Azure CLI + ssh ext; bash and PowerShell helpers reach a shell).
      *(validated on one OS; remaining OSes are incremental)*
- [x] **feas-keyring** -- *(re-scoped)* Confirm `@github/copilot` login persists headless
      via its `~/.copilot` file token (no Secret Service). Keyring stack dropped.
- [x] **feas-glyphs** -- Confirm Nerd Font glyphs + Tokyo Night render from the client
      terminal over SSH on each OS (document client setup).
- [x] **feas-baseline** -- *(resolved)* `Standard_B2as_v2`, 64 GB Standard SSD, Ubuntu
      LTS, always-on (~$87/mo, under $150 budget). Lean/heavy profile pattern kept.

### Phase 2 -- Build

- [x] **build-skeleton** -- Repo scaffold (README, `docs/`, `.gitignore`).
- [x] **build-corebuild** -- Standalone, Azure-unaware `core-build/install.sh` (idempotent,
      multi-arch, target-dir param) + `core-build/files/`: toolchain incl. **git-delta +
      lazygit (themed) + gh + Neovim-from-release (fail-loud)**, **system-wide Node +
      Copilot CLI**, LazyVim config (plugins on first `nvim`), Tokyo Night, tmux + minimal
      `.tmux.conf` + `ta` alias. **No keyring stack.**
- [x] **build-cloudinit-azure** -- Thin `cloud-init/azure/custom-data.example` overlay
      (ASCII-only): SSH hardening, **unattended-upgrades + ufw**, home-dir creation via
      AAD extension, `__ADMIN__` lockdown; **runs** the core build (does not contain it).
- [x] **build-provision** -- Provisioning script: RG, default-deny NSG, VM with
      **Trusted Launch** + managed identity + AAD SSH login, RBAC (admin login only --
      **no self-deallocate role**), Defender for Servers, per-VM JIT policy.
- [x] **build-connect** -- Cross-platform connection helpers: `connect.sh` (bash) and
      `connect.ps1` (PowerShell), both doing start-if-deallocated + JIT (current source
      or CIDR profile) + `az ssh vm` (no VNC forward).
- [x] **build-sync** -- Cross-platform file-sync helper: rsync push/pull over Entra SSH,
      **files AND directories**, **shared JIT/CIDR logic** (no duplication with connect),
      bash + PowerShell parity, dev-user ownership.
- [x] **build-vault** -- *(re-scoped)* Confirmed Copilot file-token under `~/.copilot`
      persists headless; no keyring wiring needed.
- [x] **build-clientdoc** -- Per-OS client setup doc (Azure CLI + ssh ext, Nerd Font,
      truecolor terminal, `<C-/>` / fallback toggle) for macOS/Linux/Windows. Includes a
      **Session persistence (tmux)** section.
- [x] **build-adr** -- `docs/decisions/` ADRs: 0001 access model, 0002 editor/tooling,
      0003 VM sizing/lifecycle, 0004 separable core build, 0005 host hardening, 0006
      session persistence (tmux). All generic.
- [x] **build-agentdocs** -- Generic `.github/copilot-instructions.md` + `docs/gotchas.md`
      (ASCII-only, fail-loud nvim download, apt lock, multi-range NAT-pool CIDR profile).
- [x] **build-ephemeral** -- Idempotent provisioner; delete/recreate documented as reset
      path; `docs/vm-validation.md` covers the full teardown/reprovision workflow.
- [x] **build-sharing** -- *(realized in layout)* The `core-build/` dir IS the separable
      layer (Azure-unaware, target-dir param, runnable by any invoker), consumed by the
      Azure overlay via inline-at-provision. A future rpi4/`local-dev-machine` rewrite adds
      its own thin overlay that runs the same `core-build/install.sh`.

## 8. References

- Sibling Pi project [`local-dev-machine`](https://github.com/coseguera/local-dev-machine)
  -- defines the core build layer this plan reuses, and the physical-access layer it
  drops.
