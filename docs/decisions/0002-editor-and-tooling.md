# 0002 -- Editor and tooling: LazyVim + Copilot CLI, system Node, no keyring

Status: **Accepted**

## Context

The environment is **console-only** -- no desktop, no VNC, no GUI editor. It must
feel like a complete dev setup over a bare SSH session, support an agentic AI
workflow, and seed cleanly for any user who logs in. Three sub-choices follow:
which editor stack, how to install Node (which the AI CLI needs), and how to store
the AI CLI's auth token.

## Decision

- **Editor: LazyVim** (a Neovim distribution) installed from the Neovim release
  build, themed Tokyo Night, with a Nerd Font assumed on the client. The Copilot
  CLI runs in its own tmux window alongside the editor (see
  [0008](0008-copilot-in-tmux-window.md)).
- **Node: system-wide via NodeSource**, not `nvm`. The AI CLI is installed as a
  global npm package on the system `PATH`. A system install seeds every user from
  `/etc/skel` without per-user version-manager setup, and avoids the ordering
  hazard where a per-user `nvm` must be installed *after* the home-dir is created
  and owned.
- **No system keyring.** The `@github/copilot` CLI keeps its token in a file under
  `~/.copilot`. There is nothing to unlock, so `gnome-keyring`/PAM keyring
  integration (used in an earlier experiment) is **dropped** entirely.

## Consequences

- A new user gets a fully themed, AI-ready editor on first login with no per-user
  bootstrap, because the toolchain is system-wide and dotfiles seed from `/etc/skel`.
- The client must provide truecolor + a Nerd Font for the UI to render; that
  requirement is documented in client setup.
- Dropping the keyring removes a moving part (no headless unlock problem) at the
  cost of the token living as a plain file in the user's home -- acceptable for a
  single-user VM whose disk and access are already controlled by ADR 0001/0005.
- The whole editor/toolchain layer is Azure-unaware, which enables ADR 0004.
