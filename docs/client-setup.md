# Client setup

Everything that renders the environment -- the Tokyo Night theme and Nerd Font
glyphs -- runs in **your local terminal** over SSH. The VM installs nothing for
display. This guide covers the one-time client prerequisites per OS, then how to
connect, sync files, and keep a session alive across disconnects.

## What every client needs

1. **Azure CLI + the `ssh` extension** -- the only thing that must be installed to
   connect. The helpers install the `ssh` extension automatically on first run.
2. **A truecolor terminal** -- required for the theme to render correctly.
3. **A Nerd Font** -- required for icons/glyphs in LazyVim, lualine, and the file
   tree. Set it as your terminal's font.

You do **not** need a static SSH key: login is Microsoft Entra ID SSH, which issues
a short-lived certificate per session.

---

## macOS

```sh
# Azure CLI
brew install azure-cli

# A Nerd Font (any will do; this is an example)
brew install --cask font-jetbrains-mono-nerd-font
```

- **Terminal:** the stock Terminal.app is truecolor on recent macOS; iTerm2 or
  Ghostty also work well. Set the terminal font to the Nerd Font you installed.
- Connect with `./connect.sh` (see below).

## Linux

```sh
# Azure CLI (see https://learn.microsoft.com/cli/azure/install-azure-cli-linux
# for your distro; example for Debian/Ubuntu uses the Microsoft apt repo).

# A Nerd Font: install via your package manager if available, or drop the font
# files into ~/.local/share/fonts and run `fc-cache -f`.
```

- **Terminal:** most modern terminals (GNOME Terminal, Konsole, Alacritty, Kitty,
  WezTerm, Ghostty) are truecolor. Set the terminal font to a Nerd Font.
- Connect with `./connect.sh`.

## Windows

```powershell
# Azure CLI
winget install -e --id Microsoft.AzureCLI

# A Nerd Font: install with winget, or download from nerdfonts.com and install.
winget install -e --id DEVCOM.JetBrainsMonoNerdFont   # example
```

- **Terminal:** use **Windows Terminal** (truecolor, supports Nerd Fonts). Set its
  font to the Nerd Font you installed, and connect from a **PowerShell** tab.
- Connect with `./connect.ps1`.
- `sync.ps1` additionally needs `rsync` and `ssh` on `PATH` (both come with WSL or
  Git for Windows).

---

## Connecting

From the repo directory:

```sh
./connect.sh           # macOS / Linux
./connect.ps1          # Windows (PowerShell)
```

The helper starts the VM if it is deallocated, requests Just-in-Time access for
port 22 from your current source, then opens an Entra ID SSH session. You land in a
shell; start the editor with `nvim`, and open the Copilot CLI terminal inside it
with `Ctrl+/` (fallback: `Ctrl+t`).

### Networks behind a multi-range NAT pool

By default the helper opens port 22 to your detected public IP as a `/32`, which is
correct for home and most networks. Some networks route outbound traffic through a
NAT pool, so the IP that actually reaches Azure differs from a "what's-my-IP"
lookup and may span several ranges -- a `/32` then never matches and the connection
times out. Create a **per-network profile** (gitignored, never committed) listing
the covering CIDR(s):

```sh
# connect.<name>.local
JIT_SRC=203.0.113.0/24,198.51.100.0/24
```

Then pass the profile name:

```sh
./connect.sh <name>                  # macOS / Linux
./connect.ps1 -NetworkProfile <name> # Windows
```

> Your public IP can change when you switch networks. If a connection times out,
> re-check which network you are on and whether you need a profile (or the default
> `/32`).

---

## Syncing files

`sync.sh` / `sync.ps1` do a one-way `rsync` of a **file or directory**, scp-style
(`<source>` then `<destination>`); the destination is the parent directory and the
source basename is preserved. They reuse the same access logic and network
profiles as the connect helpers, and reuse a live access window if one is already
open (e.g. a connect session running).

```sh
# macOS / Linux
./sync.sh push ~/notes /home/<you>            # local -> VM  (lands in /home/<you>/notes)
./sync.sh pull /home/<you>/out ./downloads    # VM    -> local

# Windows (PowerShell)
./sync.ps1 push C:\notes /home/<you>
./sync.ps1 pull /home/<you>/out .\downloads
```

Options: `--delete` (mirror deletions) and `--dry-run` (preview). On Windows these
are `-Delete` and `-DryRun`. Files land owned by your Entra login user on the VM.

---

## Keeping a session alive (tmux)

SSH disconnects -- a dropped network, closing the laptop, or simply stepping away
-- would otherwise kill whatever you were running. Use **tmux** on the VM so work
keeps running and you can reattach later.

### Attach and reattach

A convenience alias is preinstalled (`ta` = "attach to session `main`, or create
it"):

```sh
ta            # first time: creates and attaches to session "main"
# ... work in nvim / build / run Copilot CLI ...
# disconnect (or get disconnected) at any time
./connect.sh  # reconnect later
ta            # reattach to "main" exactly where you left off
```

You can also detach **on purpose** without closing SSH: press `Ctrl+b` then `d`. The
session keeps running; `ta` brings it back.

### tmux basics

tmux commands start with the **prefix** `Ctrl+b`, released, then a key:

| Keys | Action |
| --- | --- |
| `Ctrl+b` `d` | **detach** (leave the session running) |
| `Ctrl+b` `c` | new **window** (like a tab) |
| `Ctrl+b` `n` / `p` | next / previous window |
| `Ctrl+b` `0`..`9` | jump to window by number |
| `Ctrl+b` `,` | rename the current window |
| `Ctrl+b` `%` | split into left/right **panes** |
| `Ctrl+b` `"` | split into top/bottom panes |
| `Ctrl+b` arrow | move focus between panes |
| `Ctrl+b` `z` | zoom the current pane (toggle fullscreen) |
| `Ctrl+b` `x` | close the current pane |
| `Ctrl+b` `[` | enter **copy/scroll mode** (arrows/PageUp to scroll; `q` to exit) |
| `Ctrl+b` `?` | list all key bindings |

> Inside LazyVim you usually don't need tmux panes -- use the editor's own splits and
> the `Ctrl+/` terminal. tmux earns its keep as the **outer** layer that survives
> disconnects and lets you run long jobs in a separate window.

### Managing sessions

```sh
tmux ls                       # list sessions
tmux attach -t main           # attach to a named session (what `ta` does)
tmux new -s build             # start another named session
tmux kill-session -t build    # end a session you no longer need
```

### Important caveat -- disconnect is not deallocation

Closing the SSH session does **not** stop the VM. With the lean (always-on,
burstable) profile the VM keeps running by design, so a tmux session survives
indefinitely until the VM is rebooted or stopped. Disconnecting saves nothing on
cost; it only ends your terminal. To actually stop billing for compute you must
deallocate or delete the VM (see the provisioning docs).

## Next: learning the editor

New to Neovim/LazyVim coming from VS Code? See
[LazyVim for VS Code users](lazyvim-for-vscode-users.md) for a modal-editing primer,
a VS Code -> LazyVim cheat-sheet, and the lazygit/delta review workflow.
