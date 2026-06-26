# core-build

The **platform-agnostic** core of `azure-dev-terminal`: a single `install.sh`
plus a `files/` tree that builds the console dev environment (LazyVim + Copilot
CLI + toolchain + dotfiles). It is deliberately **Azure-unaware** -- it knows
nothing about Entra ID, cloud-init, JIT, or admin accounts -- so it can be reused
on any Debian/Ubuntu host (e.g. a Pi or laptop) under a different platform overlay.

## What it does

- Installs system-wide tools: `git`, `ripgrep`, `fd`, `fzf`, `jq`, `git-delta`,
  `tmux`, build deps, Python venv/pipx; `gh`; Node.js (NodeSource) + Copilot CLI;
  Neovim (release); lazygit (release).
- Stages dotfiles + the LazyVim config into a **target directory**:
  `.tmux.conf`, `.gitconfig`, `.bashrc.d/*`, lazygit theme, LazyVim (plugins
  install on first `nvim` run).

It uses no system keyring: the agentic `@github/copilot` CLI keeps its token in a
file under `~/.copilot`, so there is nothing to unlock.

## Usage

```sh
sudo ./install.sh [--target-dir DIR]
```

- `--target-dir /etc/skel` (default) -- a **multi-user template**: each new user's
  home is seeded from it (e.g. Entra SSH first login via `pam_mkhomedir`).
- `--target-dir "$HOME"` -- a **single machine/user** (e.g. a Pi or laptop).

Requires root (installs system packages). Re-runnable: each step guards itself.
Targets Debian/Ubuntu, `amd64` or `arm64`.

## Layout

```
install.sh                       # the installer (system tools + dotfile staging)
files/
  tmux.conf                      -> <target>/.tmux.conf
  gitconfig                      -> <target>/.gitconfig
  bashrc.d/10-azure-dev-terminal.sh -> <target>/.bashrc.d/
  lazygit/config.yml             -> <target>/.config/lazygit/config.yml
  nvim/lua/plugins/snacks.lua    -> dropped into the LazyVim config
```

## How platforms consume it

Each platform adds a **thin overlay** that does its own host setup, then runs this
core build. The Azure overlay (`cloud-init/azure/custom-data.example`) inlines this
whole directory (base64 tarball) so the deployed config is self-contained, then
runs `install.sh --target-dir /etc/skel`. A future Pi overlay would do the
equivalent for its own datasource.
