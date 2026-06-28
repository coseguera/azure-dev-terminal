# 0008 -- Run the Copilot CLI in its own tmux window

Status: **Accepted**

## Context

The earlier workflow ran the Copilot CLI **inside** Neovim's floating `Ctrl+/`
terminal, next to the editor buffers. That nests the CLI one terminal layer
deeper than necessary: the stack becomes `Copilot -> Neovim :terminal -> tmux ->
client terminal`.

[ADR 0007](0007-clipboard-over-ssh-osc52.md) makes **OSC 52** the clipboard
transport. Neovim's embedded `:terminal` does not forward an inner program's OSC
52 write cleanly to the outer terminal -- the escape leaks onto the screen as a
burst of literal base64 near the prompt and never reaches the client clipboard.
So copying Copilot CLI output fails whenever the CLI runs inside the editor's
terminal. The extra layer also complicates mouse selection and timeline
expansion.

Running the CLI directly under tmux removes that layer (`Copilot -> tmux ->
client terminal`), so its copy reaches the local clipboard. tmux is already the
**outer** session layer (ADR 0006), so a dedicated window costs nothing and
survives disconnects.

## Decision

- Run the Copilot CLI in **its own tmux window**, a peer of the editor window --
  e.g. `Ctrl+b c` for a new window, then `copilot`. Switch between editor and CLI
  with the tmux window keys (`Ctrl+b n` / `p` / `<number>`).
- The Neovim `Ctrl+/` floating terminal stays available as a **convenience**
  terminal for quick shells and test runs, but is no longer the place to run the
  Copilot CLI.
- No code or `core-build` change is required; this is a workflow + documentation
  decision. The `Ctrl+/` toggle binding is unchanged.

## Consequences

- The Copilot CLI's copy (its `Ctrl+C` OSC 52 write) reaches the client clipboard
  as clean, reflowed text instead of leaking through Neovim's `:terminal`.
- Editor and CLI live in separate tmux windows; switching is a tmux keystroke
  rather than a float toggle, and both survive an SSH disconnect.
- Client and editor docs are updated to describe the tmux-window workflow and to
  demote `Ctrl+/` to a convenience terminal.
- Selecting general terminal text still uses the client terminal's native
  selection (Shift+drag); see [client setup](../client-setup.md#copying-text-out-of-the-terminal).
