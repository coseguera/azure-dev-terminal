# 0007 -- Clipboard over SSH via OSC 52

Status: **Accepted**

## Context

Work happens in an editor and shell on the VM, but the clipboard the user pastes
into lives on their **local** machine. Over a plain SSH session a Neovim or tmux
yank lands in the VM's clipboard, which does not reach the laptop. The console
-only model rules out VNC/RDP clipboard channels, so the only transport left is
the terminal's own **OSC 52** escape sequence, which carries clipboard writes
from the remote program out to the client terminal.

Two things otherwise block a plain `y` from reaching the laptop:

- LazyVim sets `clipboard = SSH_CONNECTION and "" or "unnamedplus"`, i.e. it
  deliberately blanks the clipboard register when running over SSH.
- tmux does not forward an inner program's OSC 52 escape unless told to.

## Decision

- Rely on **OSC 52** as the clipboard transport. The client terminal must
  support it; the VM is configured to emit it. The repo stays terminal-agnostic
  -- which specific OSC 52-capable terminal the operator runs is their choice.
- tmux (`core-build/files/tmux.conf`): keep `set -g mouse on` and add
  `set -g set-clipboard on` so tmux forwards inner-program OSC 52 escapes to the
  client and routes copy-mode yanks to the client clipboard.
- Neovim (`core-build/files/nvim/lua/config/options.lua`): set
  `vim.opt.clipboard = "unnamedplus"`, overriding LazyVim's SSH-blanking default.
  Neovim's built-in OSC 52 provider is selected automatically over SSH, so a
  plain `y` syncs to the client clipboard.

## Consequences

- A Neovim/tmux yank syncs to the local clipboard automatically; mouse selection
  and scroll continue to work (`mouse on`).
- Clients without OSC 52 support cannot receive the clipboard; client docs note
  that clipboard sync requires an OSC 52-capable terminal.
- Pasting external text **into** Neovim still uses the terminal's own paste
  (clipboard read is commonly blocked by terminals for safety); in-editor paste
  of just-yanked text works from Neovim's register.
- Two one-line config additions, no extra VM software, no client software beyond
  an OSC 52-capable SSH terminal.
