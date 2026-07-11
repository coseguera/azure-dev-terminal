# 0010 -- dev-machine consumed as a provision-time clone, not a submodule

Status: **Accepted**

Supersedes the **submodule** mechanism of [ADR 0009](0009-core-build-in-dev-machine-repo.md).
The rest of ADR 0009 (dev-machine as its own flag-driven, host-unaware repo) and the
self-contained-custom-data principle of [ADR 0004](0004-separable-core-build.md) still hold.

## Context

ADR 0009 mounted `dev-machine` as a git **submodule** pinned at a commit
(`core-build/`), so that core-build upgrades were explicit and reviewable. In practice
that pinning is not currently wanted: the day-to-day workflow is "always deploy the
latest dev-machine," and the submodule adds friction -- `git submodule update --init`
on every clone, pin bumps to get changes, and a perpetually "modified" submodule entry
when iterating on the core build locally.

`dev-machine` is now **public**, and provisioning already requires an internet
connection, so a plain clone at provision time is viable and simpler.

## Decision

- Remove the submodule. `dev-machine` is consumed as a **plain local clone**, not a
  submodule.
- `provision.sh` takes a `--dev-machine-dir DIR` parameter that defaults to
  `./dev-machine` (gitignored). Whatever is on disk at that path is what gets deployed
  -- it is **never auto-pulled**, so local edits and a checked-out branch are honored.
- If `DIR/install.sh` is missing, `provision.sh` **interactively offers to clone**
  `dev-machine` (from `DEVMACHINE_URL`, default the public repo) into `DIR`, regardless
  of the location passed.
- At render time `provision.sh` prints the resolved dir + git ref/short-SHA + dirty
  state, and asks for a **final confirmation** (summarizing VM/RG/LOC/SIZE/dev-machine)
  before creating any Azure resources. A `--yes` flag skips both prompts for automation.
- The render/inline path is otherwise unchanged: the tree is tar+gzip+base64'd into
  the still self-contained, ASCII-only `custom-data` (no boot-time repo dependency).

## Consequences

- No submodule chores: a plain `git clone` of this repo is enough; `provision.sh`
  fetches the core build on first run.
- Full local control over the deployed core build: clone once, edit freely, switch
  branches, then deploy exactly what is on disk. Updating to latest is a manual
  `git pull` in the dev-machine dir (deliberately not automatic, so edits are safe).
- Version pinning is given up: there is no recorded commit that a given Azure build was
  validated against. The render-time ref/SHA/dirty echo plus the pre-provision
  confirmation mitigate this by making the deployed state visible before commit.
- The self-contained, ASCII-only custom-data guarantee from ADR 0004 is preserved; the
  inlining and ASCII guard are unchanged.
