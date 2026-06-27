#!/usr/bin/env bash
# =============================================================================
# azure-dev-terminal -- core build installer (platform-agnostic)
# -----------------------------------------------------------------------------
# Installs the system-wide developer toolchain and stages the dotfiles + LazyVim
# config into a TARGET directory. This script is intentionally Azure-UNAWARE: it
# knows nothing about Entra ID, cloud-init, JIT, NSGs, or admin accounts. It can
# be run by any invoker -- a cloud-init runcmd, a manual `sudo ./install.sh`
# session, Ansible, etc. -- on any Debian/Ubuntu host (amd64 or arm64).
#
# What it installs (system-wide, on PATH):
#   - CLI toolchain: git, ripgrep, fd, fzf, jq, git-delta, tmux, build deps,
#     Python venv/pipx
#   - gh (GitHub CLI), Node.js (NodeSource) + Copilot CLI, Neovim (release),
#     lazygit (release)
# What it stages into TARGET:
#   - .tmux.conf, .gitconfig, .bashrc.d/*, lazygit theme, LazyVim config
#     (plugins install on first `nvim` run)
#
# Usage:
#   sudo ./install.sh [--target-dir DIR]
#     --target-dir DIR   Where dotfiles are staged. Default: /etc/skel
#                        - /etc/skel  -> a multi-user template; each new user's
#                          home is seeded from it (e.g. Entra SSH + pam_mkhomedir).
#                        - a real $HOME -> a single machine/user (e.g. a Pi/laptop).
#
# Requires root (installs system packages). Re-runnable: each step guards itself.
# =============================================================================
set -uo pipefail

TARGET_DIR="/etc/skel"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --target-dir) TARGET_DIR="${2:?--target-dir needs a value}"; shift 2 ;;
    --target-dir=*) TARGET_DIR="${1#*=}"; shift ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FILES_DIR="$SCRIPT_DIR/files"

log()  { echo "[core-build] $*"; }
die()  { echo "[core-build] ERROR: $*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "must run as root (installs system packages)"
[ -d "$FILES_DIR" ] || die "files/ dir not found next to install.sh ($FILES_DIR)"

export DEBIAN_FRONTEND=noninteractive

# On a fresh cloud VM, unattended-upgrades / apt-daily timers and (under cloud-init)
# the platform's own package phase run apt CONCURRENTLY and hold the dpkg lock. Without
# this, an early `apt-get` aborts the whole build with "Could not get lock". Make EVERY
# apt invocation -- including those run by third-party setup scripts such as NodeSource --
# WAIT for the lock instead of failing. (DPkg::Lock::Timeout is honored by apt >= 1.9.11.)
if [ -d /etc/apt ]; then
  mkdir -p /etc/apt/apt.conf.d
  echo 'DPkg::Lock::Timeout "600";' > /etc/apt/apt.conf.d/99adt-lock-timeout
fi

ARCH="$(dpkg --print-architecture)"   # amd64 | arm64
case "$ARCH" in
  amd64) NVIM_ARCH="x86_64"; LG_ARCH="x86_64" ;;
  arm64) NVIM_ARCH="arm64";  LG_ARCH="arm64"  ;;
  *)     die "unsupported architecture: $ARCH" ;;
esac

# --- System packages (the dev toolchain + LazyVim deps) ----------------------
log "installing apt packages"
apt-get update -y
apt-get install -y \
  build-essential pkg-config git curl ca-certificates gnupg unzip jq \
  ripgrep fd-find fzf git-delta \
  python3-venv python3-pip pipx \
  tmux \
  || die "apt package install failed"

# --- fd symlink (Debian/Ubuntu ship the binary as fdfind) --------------------
if command -v fdfind >/dev/null 2>&1 && [ ! -e /usr/local/bin/fd ]; then
  ln -sf "$(command -v fdfind)" /usr/local/bin/fd
fi

# --- GitHub CLI from the official apt repo -----------------------------------
if ! command -v gh >/dev/null 2>&1; then
  log "installing gh"
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    -o /etc/apt/keyrings/githubcli-archive-keyring.gpg
  chmod 0644 /etc/apt/keyrings/githubcli-archive-keyring.gpg
  echo "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    > /etc/apt/sources.list.d/github-cli.list
  apt-get update -y
  apt-get install -y gh || die "gh install failed"
fi

# --- Node.js (system-wide) via NodeSource; provides node + npm on PATH -------
if ! command -v node >/dev/null 2>&1; then
  log "installing Node.js (system-wide)"
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash - || die "NodeSource setup failed"
  apt-get install -y nodejs || die "nodejs install failed"
fi

# --- Copilot CLI (system-wide global) ----------------------------------------
if ! command -v copilot >/dev/null 2>&1; then
  log "installing Copilot CLI"
  npm install -g @github/copilot || die "Copilot CLI install failed"
fi

# --- Neovim from the latest GitHub release (newer than apt) ------------------
# Fail loudly on download failure: the apt nvim is too old for current LazyVim,
# so a silent fallback would produce a confusingly broken editor.
if ! command -v nvim >/dev/null 2>&1; then
  log "installing Neovim (release)"
  TARBALL="nvim-linux-${NVIM_ARCH}.tar.gz"
  curl -fsSL -o /tmp/nvim.tar.gz \
    "https://github.com/neovim/neovim/releases/latest/download/${TARBALL}" \
    || die "Neovim release download failed (apt nvim is too old for LazyVim)"
  rm -rf /opt/nvim
  tar -C /opt -xzf /tmp/nvim.tar.gz
  mv "/opt/nvim-linux-${NVIM_ARCH}" /opt/nvim
  ln -sf /opt/nvim/bin/nvim /usr/local/bin/nvim
  rm -f /tmp/nvim.tar.gz
fi

# --- lazygit from the latest GitHub release ----------------------------------
if ! command -v lazygit >/dev/null 2>&1; then
  log "installing lazygit"
  LG_VER="$(curl -fsSL https://api.github.com/repos/jesseduffield/lazygit/releases/latest \
            | jq -r '.tag_name' | sed 's/^v//')"
  if [ -n "$LG_VER" ] && [ "$LG_VER" != "null" ]; then
    curl -fsSL -o /tmp/lazygit.tar.gz \
      "https://github.com/jesseduffield/lazygit/releases/latest/download/lazygit_${LG_VER}_Linux_${LG_ARCH}.tar.gz" \
      || die "lazygit download failed"
    tar -C /usr/local/bin -xzf /tmp/lazygit.tar.gz lazygit
    rm -f /tmp/lazygit.tar.gz
  else
    die "could not resolve latest lazygit version"
  fi
fi

# --- Stage dotfiles into TARGET ----------------------------------------------
log "staging dotfiles into $TARGET_DIR"
mkdir -p "$TARGET_DIR/.bashrc.d" "$TARGET_DIR/.config/lazygit"
install -m 0644 "$FILES_DIR/tmux.conf"  "$TARGET_DIR/.tmux.conf"
install -m 0644 "$FILES_DIR/gitconfig"  "$TARGET_DIR/.gitconfig"
install -m 0644 "$FILES_DIR/bashrc.d/"*.sh "$TARGET_DIR/.bashrc.d/"
install -m 0644 "$FILES_DIR/lazygit/config.yml" "$TARGET_DIR/.config/lazygit/config.yml"

# --- Ensure TARGET .bashrc sources ~/.bashrc.d/*.sh --------------------------
touch "$TARGET_DIR/.bashrc"
if ! grep -q 'bashrc.d/\*.sh' "$TARGET_DIR/.bashrc" 2>/dev/null; then
  cat >> "$TARGET_DIR/.bashrc" <<'RC'

# azure-dev-terminal: load drop-in shell config
if [ -d "$HOME/.bashrc.d" ]; then
  for _rc in "$HOME"/.bashrc.d/*.sh; do
    [ -r "$_rc" ] && . "$_rc"
  done
  unset _rc
fi
RC
fi

# --- Stage the LazyVim config into TARGET ------------------------------------
# Only the config is staged; Lazy.nvim installs plugins on the first `nvim` run.
# Keeps the build simple -- one git clone, no headless sync -- at the cost of a
# one-time plugin download the first time nvim opens.
SKEL_NVIM="$TARGET_DIR/.config/nvim"
if [ ! -e "$SKEL_NVIM/init.lua" ]; then
  log "staging LazyVim config into $TARGET_DIR"
  mkdir -p "$TARGET_DIR/.config"
  git clone --depth 1 https://github.com/LazyVim/starter "$SKEL_NVIM" \
    || die "LazyVim starter clone failed"
  rm -rf "$SKEL_NVIM/.git"
  mkdir -p "$SKEL_NVIM/lua/plugins"
  install -m 0644 "$FILES_DIR/nvim/lua/plugins/snacks.lua" \
    "$SKEL_NVIM/lua/plugins/snacks.lua"
  # Override options.lua to route yanks through the OSC 52 system clipboard.
  install -m 0644 "$FILES_DIR/nvim/lua/config/options.lua" \
    "$SKEL_NVIM/lua/config/options.lua"
fi

# --- Normalize ownership/permissions of the staged paths ---------------------
# Match the TARGET dir's owner (root:root for /etc/skel; the user for a real
# $HOME), so a root-run install does not leave root-owned files in a user home.
owner="$(stat -c '%U' "$TARGET_DIR")"
group="$(stat -c '%G' "$TARGET_DIR")"
for p in .tmux.conf .gitconfig .bashrc .bashrc.d .config/nvim .config/lazygit; do
  [ -e "$TARGET_DIR/$p" ] || continue
  chown -R "$owner:$group" "$TARGET_DIR/$p"
  find "$TARGET_DIR/$p" -type d -exec chmod 0755 {} +
done

log "core build complete (target: $TARGET_DIR)"
