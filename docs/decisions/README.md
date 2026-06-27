# Architecture decision records

These ADRs capture the **why** behind the durable design choices in this repo.
Each is self-contained and uses a lightweight format: Context, Decision,
Consequences. They are written fresh for `azure-dev-terminal` and kept generic.

| ADR | Title |
|---|---|
| [0001](0001-access-model.md) | Access model: Entra ID SSH + Just-in-Time, no static keys |
| [0002](0002-editor-and-tooling.md) | Editor and tooling: LazyVim + Copilot CLI, system Node, no keyring |
| [0003](0003-vm-sizing-and-lifecycle.md) | VM sizing, burstability, and lifecycle |
| [0004](0004-separable-core-build.md) | A separable, platform-agnostic core build |
| [0005](0005-host-hardening.md) | Host hardening baseline |
| [0006](0006-session-persistence-tmux.md) | Session persistence via tmux |
| [0007](0007-clipboard-over-ssh-osc52.md) | Clipboard over SSH via OSC 52 |

Status values: **Accepted** (in effect), **Superseded** (replaced by a later ADR).
