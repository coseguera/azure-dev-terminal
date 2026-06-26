# Gotchas

Hard-won traps in provisioning and connecting to this VM. Each is generic.

## ASCII-only custom-data

`az vm create` passes `custom-data` through a latin-1/ASCII-sensitive path: a single
non-ASCII byte (em-dash, smart quote, accented char) aborts creation with a codec
error. Because `provision.sh` **inlines the entire `core-build/` tree** into
`custom-data`, this applies to every file that gets inlined, not just the overlay.

- Keep all inlined content ASCII. Use `-` not the em/en dash, straight quotes only.
- Verify before provisioning:
  ```sh
  LC_ALL=C grep -nP '[^\x00-\x7F]' <rendered-custom-data>   # any output = a bad byte
  ```

## apt/dpkg lock race on first boot

On a freshly booted cloud VM, `cloud-init` and `unattended-upgrades` run their own
`apt` phase that holds `/var/lib/dpkg/lock-frontend` **concurrently** with the core
build's `apt-get`. Without a wait, an early `apt-get install` fails *instantly*
("Could not get lock ... held by process N") and aborts the whole build -- while
cloud-init may still report overall success.

- Fix in place: `install.sh` writes `/etc/apt/apt.conf.d/99adt-lock-timeout` with
  `DPkg::Lock::Timeout "600";` early, so apt **waits** for the lock instead of failing
  (honored by apt >= 1.9.11; covers child apt invocations such as NodeSource's).
- Don't remove the lock-timeout config or assume the lock is free at boot.
- This was reproduced on a cold boot (log: "Waiting for cache lock ... held by
  process ...") and confirmed to wait it out and succeed.

## Fail-loud core build

cloud-init `runcmd` does **not** `set -e`, so a failed `install.sh` was previously
masked by the boot's final "success" message. The overlay now runs the build as
`install.sh || { echo FAILED > .../core-build.status; echo "CORE BUILD FAILED" >&2;
exit 1; }` and writes an `OK` sentinel otherwise. When debugging a "succeeded but
tools are missing" VM, check the `core-build.status` sentinel and the cloud-init
output log first.

## NAT-pools / multi-range egress for JIT

JIT opens port 22 to a **source**. By default the helpers detect your public IP and
open a `/32` -- correct for home and most networks. But some networks egress through
a **NAT pool**: the IP that actually reaches Azure differs from a "what's-my-IP"
lookup and rotates across several addresses/ranges, so a `/32` never matches and the
connection times out.

- Create a gitignored `connect.<name>.local` with a **covering CIDR** (e.g.
  `JIT_SRC=203.0.113.0/24,198.51.100.0/24`) and pass the profile name.
- Never commit real ranges -- profiles are `*.local` and gitignored by design.
- Symptom: SSH times out *after* JIT reports success. Re-check your egress address vs
  what JIT allowed.

## Source IP changes between networks

Your public IP changes when you switch networks. A profile built for one network
won't match another; the default auto-detected `/32` works when you're *not* behind a
NAT pool. If a connection that worked yesterday times out, re-check which network
you're on before assuming a provisioning bug.

## PowerShell `$Profile` shadowing

`$Profile` is an automatic PowerShell variable (path to the user's profile script).
Naming a parameter `$Profile` silently shadows it. Use `$NetworkProfile` for the
network-profile parameter in the `.ps1` helpers.

## az CLI surface drift

Flags and output shapes vary between `az` versions. Before relying on a flag
(`az ssh config`, `az ssh vm`, `az rest`, `az vm show -d --query ...`), confirm it
against the installed CLI's `--help`. Pin assumptions to verified behavior, not
memory.
