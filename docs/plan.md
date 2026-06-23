# Project plan: `azure-dev-terminal` -- console-first, SSH-only Azure dev VM

> Status: design + phased build plan. Seeded from a proposal that distills a
> console-first **LazyVim + Copilot CLI** environment (already built and
> hardware-validated on a Raspberry Pi in the sibling project
> [`local-dev-machine`](https://github.com/coseguera/local-dev-machine)) and re-targets
> it at an **Azure VM reached purely over SSH**. No desktop, no VNC. The client works
> on **macOS, Linux, and Windows**.

## 0. Current status

**Stage: design / not yet built.** Nothing is provisioned yet. The core build layer
this plan reuses (LazyVim, Tokyo Night, Nerd Font glyphs, Copilot CLI via nvm + Node,
encrypted token vault, `localuser` account) is already proven on a Pi via a single
cloud-init config; the work here is to port that core build to an Azure
`--custom-data` config and pair it with an SSH-only access layer built on **Entra ID
SSH + Just-in-Time (JIT) network access**, dropping all physical-host and GUI
machinery. The connection flow must be **cross-platform** (macOS, Linux, Windows).

**Next action:** stand up a first VM from a minimal core-build `--custom-data`, reach
it over Entra ID SSH with a JIT-opened port 22, and confirm LazyVim + Copilot CLI + a
headless token vault work, with glyphs/theme rendering from the client terminal
(`feas-customdata`, `feas-access`, `feas-keyring`).

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
| **Core build** | LazyVim, Tokyo Night, Nerd Fonts, Copilot CLI (nvm + Node), keyring vault, dotfiles | same idea (subset) | **keep -- fully portable** |
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
- **Copilot CLI** via nvm + Node.
- **Encrypted token vault** -- gnome-keyring Secret Service unlocked via PAM (requires
  the separate `libpam-gnome-keyring` package; the daemon package alone is not enough).
- **Dotfiles / profile** scaffolding and a `localuser`-style account.

Mechanically these are cloud-init `write_files` + `runcmd` steps; the same cloud-init
engine runs on Azure, so most copy over directly.

### Gets dropped

- **Physical access layer:** USB gadget (CDC-ECM/libcomposite/`dwc2`), local console
  (cage + foot), Wi-Fi country/rfkill, HDMI/KMS, NetworkManager `usb0` drop-in.
- **GUI layer:** VNC server, desktop environment, the VNC port-forward, and all GUI
  session plumbing. (Dropping the tunnel is also what makes the client cross-platform --
  no OS-specific screen-sharing step.)

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

### 3e. Source selection for JIT (the part that bites behind corp NAT)

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

### 3h. Headless keyring

A headless VM has no graphical login session, so gnome-keyring auto-unlock needs the
same headless PAM handling proven on the Pi (`libpam-gnome-keyring` + a login that
drives PAM). Validate early -- this is the most likely Azure-specific snag.

### 3i. Ephemerality model

"Throwaway" = **deallocate or delete** the VM and recreate from `--custom-data`. Give
the VM's managed identity a tightly-scoped RBAC role so it can start/stop/deallocate
**only itself**, and let the connection helper start it when deallocated. The
reproducibility guarantee matches the Pi's reflash; only the reset mechanism differs.

### 3j. VM baseline

Pick image (Ubuntu LTS vs Debian to match the Pi's Bookworm), size/SKU, and disk --
the cheapest that runs Copilot CLI comfortably. (A very small host was too sluggish for
interactive Copilot CLI on the Pi side; size up rather than under-provision.) Keep a
lean and a beefier size profile so the host can be tuned per session.

## 4. Phase 2 -- Build plan

1. **Skeleton** -- repo scaffold (README, `docs/`, `.gitignore` for secret overlays and
   network profiles).
2. **Core-build custom-data** -- port the Pi's core-build cloud-init steps into an
   Azure `--custom-data` file (ASCII-only): toolchain, nvm + Node + Copilot CLI,
   LazyVim clone + headless `:Lazy! sync`, Tokyo Night, keyring + PAM, the dev account.
3. **Provisioning script** -- create RG, default-deny NSG, VM with managed identity +
   AAD SSH login extension, RBAC for admin login and for self start/stop, enable
   Defender for Servers, and create the per-VM JIT policy for port 22.
4. **Connection helpers (cross-platform)** -- a `bash` `connect.sh` (macOS/Linux) and a
   PowerShell `connect.ps1` (Windows): start-if-deallocated, request JIT for the current
   source or a selected per-network CIDR profile, then `az ssh vm` straight into a shell
   (no VNC port-forward). Both read the same gitignored profile files.
5. **Headless vault validation** -- confirm the token vault unlocks without a GUI.
6. **Client setup doc (per OS)** -- Azure CLI + ssh extension, Nerd Font + truecolor
   terminal for macOS/Linux/Windows, and the `<C-/>` / fallback toggle note (no VM-side
   rendering).
7. **Ephemerality** -- document delete/recreate as the reset path; ensure the
   provisioner is idempotent.

## 5. Open questions to resolve during Phase 1

- **Sharing the core build across hosts.** The core build is the single source of truth
  for both the Pi project and this one. Options: a git submodule, a generated
  include/snippet each repo splices into its cloud-init, or a small templating step.
  Submodule is simplest to start; templating scales better if the layers diverge.
- **VM baseline.** Final image, size/SKU, and disk; lean vs beefy profiles.
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
- **ASCII-only `--custom-data`.** Enforced (see 3b).
- **Identity-based, on-demand access.** Entra ID SSH only; port 22 closed until JIT
  opens it; no standing inbound rule.
- **Cross-platform client.** macOS, Linux, and Windows are all first-class; keep the
  helpers and client docs in sync across them.
- **Client renders display.** The VM installs nothing for glyphs/theme.
- **Reproducible & throwaway.** Always recreatable from `--custom-data`.

## 7. Todo checklist

### Phase 1 -- Feasibility (do these first; few hard inter-deps)

- [ ] **feas-customdata** -- Port a minimal core build to Azure `--custom-data`; confirm
      cloud-init runs to completion on the Azure datasource.
- [ ] **feas-ascii** -- Enforce/verify pure-ASCII custom-data in the build pipeline.
- [ ] **feas-access** -- Validate Entra ID SSH (AAD login extension + managed identity +
      RBAC) end to end; confirm the local account cannot SSH and no static key works.
- [ ] **feas-jit** -- Confirm default-deny NSG + JIT opens port 22 on demand and
      auto-closes (Defender for Servers Plan 2 enabled).
- [ ] **feas-source** -- Confirm `/32` default and per-network CIDR profile both work
      (incl. a NAT-pool network); keep all CIDRs gitignored.
- [ ] **feas-crossplatform** -- Confirm the connect flow works from macOS, Linux, and
      Windows (Azure CLI + ssh ext; bash and PowerShell helpers reach a shell).
- [ ] **feas-keyring** -- Validate headless gnome-keyring unlock via PAM on Azure.
- [ ] **feas-glyphs** -- Confirm Nerd Font glyphs + Tokyo Night render from the client
      terminal over SSH on each OS (document client setup).
- [ ] **feas-baseline** -- Choose image, size/SKU, and disk that run Copilot CLI well.

### Phase 2 -- Build

- [ ] **build-skeleton** -- Repo scaffold (README, `docs/`, `.gitignore`). *(this change)*
- [ ] **build-customdata** -- Full core-build `--custom-data`: toolchain, nvm + Node +
      Copilot CLI, LazyVim + headless sync, Tokyo Night, keyring + PAM, dev account.
      *(needs: feas-customdata)*
- [ ] **build-provision** -- Provisioning script: RG, default-deny NSG, VM + managed
      identity + AAD SSH login, RBAC (admin login + self start/stop), Defender for
      Servers, per-VM JIT policy. *(needs: feas-access, feas-jit)*
- [ ] **build-connect** -- Cross-platform connection helpers: `connect.sh` (bash) and
      `connect.ps1` (PowerShell), both doing start-if-deallocated + JIT (current source
      or CIDR profile) + `az ssh vm` (no VNC forward). *(needs: build-provision,
      feas-source, feas-crossplatform)*
- [ ] **build-vault** -- Headless token-vault unlock wired and validated.
      *(needs: build-customdata, feas-keyring)*
- [ ] **build-clientdoc** -- Per-OS client setup doc (Azure CLI + ssh ext, Nerd Font,
      truecolor terminal, `<C-/>` / fallback toggle) for macOS/Linux/Windows.
      *(needs: build-customdata)*
- [ ] **build-ephemeral** -- Idempotent provisioner; document delete/recreate reset path.
      *(needs: build-customdata)*
- [ ] **build-sharing** -- Decide and implement how the core build is shared with the Pi
      project (submodule / include / templating). *(needs: build-customdata)*

## 8. References

- Sibling Pi project [`local-dev-machine`](https://github.com/coseguera/local-dev-machine)
  -- defines the core build layer this plan reuses, and the physical-access layer it
  drops.
