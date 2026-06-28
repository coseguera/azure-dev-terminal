# LazyVim for VS Code users

A ramp-up guide for editing and reviewing code on the dev VM with **terminal-native**
tools instead of VS Code. Everything here is pre-installed by the core build:

- **Neovim + [LazyVim](https://www.lazyvim.org/)** -- a "batteries included" Neovim setup
  (LSP, autocomplete, fuzzy finder, file tree, Treesitter), themed **Tokyo Night**. This is
  your editor: `nvim` (or `nvim .` to open a project).
- **[lazygit](https://github.com/jesseduffield/lazygit)** -- a terminal UI for reviewing
  changes, staging hunks, committing, branching, and reading history. Opens inside Neovim with
  `<leader>gg` (the leader key is `Space`).
- **[git-delta](https://github.com/dandavison/delta)** -- syntax-highlighted, side-by-side
  `git diff` / `git show` / `git log -p` (wired in as git's pager).
- **ripgrep / fd / fzf** -- fast text and file search that power LazyVim's pickers.
- **[Copilot CLI](https://github.com/github/copilot-cli)** -- the agentic AI assistant. Run
  `copilot` in its own **tmux window** alongside the editor (see [Work with the Copilot
  CLI](#work-with-the-copilot-cli)).

> This box is **console-only** -- there is no desktop, no VS Code, no VNC. The whole point is a
> fast, terminal-native workflow that pairs naturally with the Copilot CLI. See
> [decision 0002](decisions/0002-editor-and-tooling.md).

---

## The one big mental shift: modal editing

VS Code is always in "insert" mode -- you type and text appears. **Vim/Neovim is modal**: the
keyboard does different things depending on the mode you're in.

| Mode | What it's for | How to get there |
| --- | --- | --- |
| **Normal** | Move around, run commands, delete/copy (the "home" mode) | press `Esc` |
| **Insert** | Actually type text (like VS Code) | press `i` (insert) or `a` (append) |
| **Visual** | Select text | press `v` (char), `V` (line), `Ctrl+v` (block) |
| **Command** | Run `:` commands (save, quit, search/replace) | press `:` |

You'll spend most time in **Normal** mode and dip into Insert to type. The reflex to build:
**hit `Esc` when you're done typing.**

### Survival kit (memorize these five first)

| Keys | Action |
| --- | --- |
| `i` then type, then `Esc` | insert text, then return to Normal mode |
| `:w` `Enter` | save (write) |
| `:q` `Enter` | quit (`:q!` to quit without saving, `:wq` to save and quit) |
| `u` / `Ctrl+r` | undo / redo |
| `:` then type | run a command |

If you ever feel lost, press `Esc` a couple of times -- you're back in Normal mode.

---

## The leader key + discoverability (your "command palette")

LazyVim's **leader key is the Spacebar**. Press **`Space`** and **wait** -- a menu
(**which-key**) pops up showing every shortcut grouped by category:

- `Space f` -- **f**ind (files, recent, buffers)
- `Space s` -- **s**earch (grep text, symbols, help, keymaps)
- `Space g` -- **g**it (lazygit, hunks)
- `Space c` -- **c**ode (rename, code action, format)
- `Space b` -- **b**uffers
- `Space x` -- diagnostics / quickfix (the "Problems" panel)
- `Space w` -- **w**indows (splits)
- `Space q` -- **q**uit

This is how you *discover* LazyVim -- just press `Space` and read. Two especially handy ones:

- `Space s k` -- **search keymaps** (fuzzy-find any shortcut by name).
- `:Tutor` `Enter` -- opens the built-in interactive Vim tutorial (~30 min, highly recommended).

---

## VS Code -> LazyVim cheat-sheet

| VS Code | LazyVim | Notes |
| --- | --- | --- |
| `Ctrl/Cmd+P` Go to File | `Space Space` (or `Space f f`) | fuzzy file finder |
| `Ctrl/Cmd+Shift+F` Search in files | `Space /` (or `Space s g`) | live grep (ripgrep) |
| `Ctrl/Cmd+Shift+E` Explorer | `Space e` | toggles the Neo-tree file explorer |
| `Ctrl/Cmd+Shift+P` Command Palette | `Space` (which-key) or `:` | discover/run commands |
| Toggle Terminal | `Ctrl+/` | floating terminal for a quick shell / test run |
| `F12` Go to Definition | `g d` | |
| `Shift+F12` References | `g r` | |
| Hover docs | `K` | (capital K) |
| `Ctrl/Cmd+.` Quick Fix | `Space c a` | LSP code action |
| `F2` Rename symbol | `Space c r` | project-wide rename |
| `Ctrl/Cmd+S` Save | `Ctrl+s` (or `:w`) | |
| `Ctrl/Cmd+/` Toggle comment | `g c c` (line), `g c` (visual selection) | |
| `Ctrl/Cmd+W` Close editor | `Space b d` | close buffer |
| `Ctrl+Tab` Switch tabs | `Shift+h` / `Shift+l` | prev / next buffer |
| Split editor | `Space \|` (vertical), `Space -` (horizontal) | |
| Focus editor group | `Ctrl+h/j/k/l` | move between splits |
| Problems panel | `Space x x` (Trouble); `]d` / `[d` next/prev diagnostic | |
| Source Control | `Space g g` | opens lazygit |
| Format document | `Space c f` | |
| Go Back / Forward | `Ctrl+o` / `Ctrl+i` | jump list |
| `Ctrl/Cmd+Shift+O` Symbols | `Space s s` | document symbols |
| Multi-cursor | Visual Block `Ctrl+v` then `I`/`A`, or `:%s/old/new/g` | different paradigm -- see below |

> **Multi-cursor**: Vim solves "edit many places at once" differently. For columns, use
> **Visual Block** (`Ctrl+v`, select lines, `I` to insert at start / `A` to append, then `Esc`).
> For find-and-replace, use `:%s/old/new/g` (add `c` for confirm: `:%s/old/new/gc`).

---

## Common workflows

### Open a project
`cd ~/my-project && nvim .` opens Neovim in the project; `Space e` shows the tree. LazyVim
treats the git root as the project root for pickers.

### Find a file / search text
- File by name: `Space Space`, type a few letters, `Enter`.
- Text across the project: `Space /`, type your query, `Enter`; results open in a picker
  (press `Enter` to jump, or `Ctrl+q` to send all results to the quickfix list).

### Edit with LSP (IntelliSense)
LazyVim auto-installs language servers via **Mason** the first time you open a file type
(needs internet once). Then: `g d` go to definition, `K` hover, `Space c a` code action,
`Space c r` rename, `]d`/`[d` to walk diagnostics, `Space c f` to format. Autocomplete pops up
as you type in Insert mode; `Enter` accepts.

### Review changes (your VS Code "Source Control" tab)
Press **`Space g g`** to open **lazygit** inside Neovim:
- Left panels list **Status / Files / Branches / Commits / Stash**; use arrow keys or `j`/`k`.
- On the **Files** panel: `Space` stages/unstages a file, `Enter` drills into per-line hunks
  (then `Space` stages individual hunks), `c` commits, `P` pushes, `p` pulls.
- Press `?` anytime for lazygit's own help; `q` to quit back to Neovim.

From a plain shell you also get pretty diffs for free thanks to delta:
`git diff`, `git show HEAD`, `git log -p` are all syntax-highlighted and side-by-side.

### Work with the Copilot CLI
Run the Copilot CLI in **its own tmux window**, not nested in the editor's terminal. From
your tmux session (`ta`), open a new window with `Ctrl+b c`, run `copilot` there, and switch
between it and the editor window with `Ctrl+b n` / `Ctrl+b p` (or `Ctrl+b <number>`). Ask the
CLI to make changes, then switch back to the editor window to review them with the LSP and
lazygit.

> **Why a tmux window and not the `Ctrl+/` float?** The CLI copies via OSC 52, and Neovim's
> embedded `:terminal` does not forward that escape cleanly -- run inside the float, the CLI's
> copy leaks onto the screen as base64 and never reaches your clipboard. One layer shallower
> (under tmux directly) it copies fine. See
> [client setup](client-setup.md#copying-text-out-of-the-terminal) and
> [ADR 0008](decisions/0008-copilot-in-tmux-window.md).

The `Ctrl+/` floating terminal is still useful as a **convenience** terminal -- a quick shell
or a test run without leaving the editor. (LazyVim also provides `<leader>ft` / `<leader>fT`
under the **file/find** menu to open a terminal in the root dir / cwd.) A plain `Ctrl+/`
toggles terminal **1**; prefix a count (`2 Ctrl+/`, `3 Ctrl+/`, ...) to open additional ones.

**Expanding collapsed Copilot CLI output (`Ctrl+O`).** The CLI's timeline collapses long tool
output (e.g. "36 lines read"). Press **`Ctrl+O`** (or `Ctrl+E`) in the CLI to "expand all
timeline" -- a keystroke that works regardless of mouse mode.

### Windows, buffers, terminal
- Open files become **buffers**; cycle with `Shift+h` / `Shift+l`, close with `Space b d`.
- Split the view: `Space \|` / `Space -`; move focus with `Ctrl+h/j/k/l`.
- Toggle a convenience terminal with `Ctrl+/` (handy for a quick shell or test run; run the
  Copilot CLI in its own tmux window instead).

---

## A tiny bit of motion vocabulary (pays off fast)

You don't need all of Vim, but these motions make editing feel fast. In **Normal** mode:

| Keys | Move / act |
| --- | --- |
| `h j k l` | left / down / up / right |
| `w` / `b` | next / previous word |
| `0` / `$` | start / end of line |
| `gg` / `G` | top / bottom of file |
| `Ctrl+d` / `Ctrl+u` | half-page down / up |
| `/text` `Enter` | search forward (`n`/`N` next/prev match) |
| `dd` / `yy` / `p` | delete line / yank (copy) line / paste |
| `ciw` | change inner word (deletes the word, drops you in Insert) |
| `ci"` / `ci(` | change inside quotes / parentheses |

The pattern is **verb + motion**: `d` (delete) + `w` (word) = `dw`. `y` (yank) + `$` = copy to
end of line. Learn a few verbs (`d`, `c`, `y`) and a few motions and they combine.

> **Getting yanked text onto your local machine**: with an OSC 52-capable
> terminal (most modern terminals), yanking in Neovim syncs to your laptop
> clipboard automatically over SSH -- a plain `y` and then paste on your laptop
> just works.

---

## Learning resources

**Read**
- [LazyVim documentation](https://www.lazyvim.org/) -- the official site (installation,
  features, configuration).
- [LazyVim keymaps reference](https://www.lazyvim.org/keymaps) -- the full default keymap list.
- [LazyVim for Ambitious Developers](https://lazyvim-ambitious-devs.phillips.codes/) -- an
  excellent **free online book** that walks you through LazyVim from scratch.
- [LazyVim on GitHub](https://github.com/LazyVim/LazyVim) and the
  [starter config](https://github.com/LazyVim/starter).
- [Neovim user manual](https://neovim.io/doc/user/) -- and `:Tutor` inside Neovim for the
  hands-on basics.

**Watch (YouTube)**
- [Zero to IDE with LazyVim](https://www.youtube.com/watch?v=N93cTbtLCIM) (Elijah Manor) -- a
  full tour of using LazyVim as your IDE.
- [Effective Neovim: Instant IDE](https://www.youtube.com/watch?v=stqUbv-5u2s) (TJ DeVries, a
  Neovim core maintainer) -- great for understanding what's happening under the hood.
- Channels worth a look: [typecraft](https://www.youtube.com/@typecraft_dev) (beginner
  "Neovim for Newbs" series), [Josean Martinez](https://www.youtube.com/@joseanmartinez),
  [TJ DeVries](https://www.youtube.com/@teej_dv).

---

## Quick reference card

```
MODES        Esc=Normal   i/a=Insert   v/V/Ctrl+v=Visual   :=Command
SAVE/QUIT    :w  :q  :wq  :q!          UNDO/REDO  u / Ctrl+r
LEADER       Space  (press and wait for the menu)
FIND         Space Space (files)   Space / (grep text)   Space e (file tree)
CODE         gd def   K hover   Space ca action   Space cr rename   Space cf format
DIAGNOSTICS  ]d / [d next/prev    Space xx (Trouble panel)
GIT          Space gg (lazygit)
BUFFERS      Shift+h / Shift+l switch    Space bd close
WINDOWS      Space | / Space -  split    Ctrl+h/j/k/l  move    Ctrl+/ terminal (quick shell)
HELP         :Tutor   Space sk (search keymaps)   ? inside lazygit
```
