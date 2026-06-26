# 0006 -- Session persistence via tmux

Status: **Accepted**

## Context

SSH sessions drop -- flaky networks, a closed laptop, stepping away. Without a
persistence layer, an interrupted connection kills whatever was running (a build, a
long Copilot CLI task, an editor with unsaved buffers). Heavier remote-session
schemes (mosh, remote desktop, VNC) were rejected as out of scope for a console-only
box; the question is purely how to survive a dropped terminal.

## Decision

- Install **tmux** as part of the core build, with a minimal Tokyo Night
  `.tmux.conf` and a convenience alias **`ta`** (`tmux attach -t main || tmux new -s
  main`).
- Make it **opt-in**, not auto-started on login: the user runs `ta` when they want a
  persistent session. Login stays fast and scriptable, and non-interactive sessions
  (sync, one-off commands) are unaffected.

## Consequences

- Work started inside `ta` survives SSH disconnects; reconnecting and running `ta`
  again reattaches exactly where the user left off.
- tmux persistence is bounded by the **VM's** lifetime, not the SSH session's:
  it survives disconnects but **not** a VM reboot or deallocation. On the lean
  always-on profile (ADR 0003) the VM does not stop on its own, so sessions persist
  indefinitely; this distinction (disconnect != deallocate) is emphasized in client
  docs.
- One small dependency and one dotfile; no client-side software beyond an SSH
  terminal.
