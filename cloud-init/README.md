# cloud-init core build

`custom-data.example` is the **committed template** for the Azure `--custom-data`
config that builds the core dev environment on first boot. `provision.sh` renders a
filled copy named `custom-data` (gitignored) by substituting placeholders, and passes
it to `az vm create --custom-data`.

## What it does

- Installs the system-wide toolchain: Neovim (release), lazygit, `gh`, git-delta,
  ripgrep/fd/fzf, tmux, Node.js (system-wide) + Copilot CLI, gnome-keyring.
- Stages the **LazyVim config** plus dotfiles (`.tmux.conf`, `.gitconfig`,
  shell rc, lazygit theme) into **`/etc/skel`**.
- Hardens the host: SSH (no passwords/root/X11), `ufw`, `unattended-upgrades`.
- Locks the local admin account out of SSH and sudo.

## Account model

This VM is reached purely over **Microsoft Entra ID SSH**. On first login your home
directory is created from `/etc/skel` (via `pam_mkhomedir`), so you land directly in a
ready LazyVim + Copilot CLI environment **as your Entra identity** -- there is no fixed
dev account. The local admin account from `az vm create` is locked down at the end.

The core build is intentionally kept **self-contained and separable** (system-wide
tools + `/etc/skel`), so it can later be reused by other projects.

## Constraints

- **Pure ASCII only.** A non-ASCII byte breaks `az vm create`. Verify:
  `LC_ALL=C grep -nP '[^\x00-\x7F]' custom-data.example`
- **Idempotent** where practical; "reset" = delete + recreate the VM.
- The VM installs **no fonts** -- glyphs/theme render in the client terminal.

## Placeholders

| Placeholder | Substituted with |
|---|---|
| `__ADMIN__` | the `az vm create --admin-username` value (locked out at the end) |

## Validate locally

```sh
LC_ALL=C grep -nP '[^\x00-\x7F]' custom-data.example   # must print nothing
cloud-init schema --config-file custom-data.example     # "Valid schema"
```
