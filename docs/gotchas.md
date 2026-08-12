# Gotchas

Hard-won traps in provisioning and connecting to this VM. Each is generic.

## ASCII-only custom-data

`az vm create` passes `custom-data` through a latin-1/ASCII-sensitive path: a single
non-ASCII byte (em-dash, smart quote, accented char) aborts creation with a codec
error. Because `provision.sh` **inlines the entire dev-machine core build tree** into
`custom-data`, this applies to every file that gets inlined, not just the overlay.
(`provision.sh` inlines the **dev-machine core build tree** from `--dev-machine-dir`.)

- Keep all inlined content ASCII. Use `-` not the em/en dash, straight quotes only.
- Verify before provisioning:
  ```sh
  LC_ALL=C grep -n "[^$(printf '\01-\177')]" <rendered-custom-data>   # any output = a bad byte
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

### Debugging it by hand

Three commands cover it (`RG`/`NSG` as in your VM config; the NSG is `<vm>-nsg`):

```sh
# 1. What is my egress address, and does it rotate? Repeat over a few minutes:
#    more than one answer = NAT pool, so a /32 will never hold.
for i in 1 2 3; do curl -s4 https://api.ipify.org; echo; sleep 5; done

# 2. What does the NSG allow right now? JIT writes one Allow rule per request.
az network nsg rule list -g "$RG" --nsg-name "$NSG" \
  --query "sort_by([?direction=='Inbound'].{prio:priority,name:name,access:access,port:to_string(destinationPortRange||destinationPortRanges),src:to_string(sourceAddressPrefix||sourceAddressPrefixes)}, &prio)" \
  -o table

# 3. Drop a stale Allow rule (name from step 2). Failed attempts leave one each.
az network nsg rule delete -g "$RG" --nsg-name "$NSG" -n "<rule-name>"
```

If your address from step 1 is not inside a `src` from step 2, that mismatch is the
timeout. Delete only the `Allow` rules -- the JIT `Deny` rule is what keeps port 22
closed by default. Rules also expire on their own at the end of the JIT window.

Control test before widening ranges: `nc -vz -G 5 github.com 22`. If that fails, the
network blocks outbound 22 and no source range will help.

## Source IP changes between networks

Your public IP changes when you switch networks. A profile built for one network
won't match another; the default auto-detected `/32` works when you're *not* behind a
NAT pool. If a connection that worked yesterday times out, re-check which network
you're on before assuming a provisioning bug.

## PowerShell `$Profile` shadowing

`$Profile` is an automatic PowerShell variable (path to the user's profile script).
Naming a parameter `$Profile` silently shadows it. Use `$NetworkProfile` for the
network-profile parameter in the `.ps1` helpers.

## az ssh: "No module named 'rpds.rpds'" (macOS)

`connect.sh` (and `sync.sh`) fail at the "Opening Entra ID SSH session ..." step with
`No module named 'rpds.rpds'`. The `az ssh vm` command loads `jsonschema`, whose native
`rpds-py` dependency is broken in the Azure CLI's bundled Python -- typically after a
Python/CLI upgrade or an x86/arm64 wheel mismatch. The same helper works from a client
with a healthy install (e.g. Linux), so it looks like a per-machine "it works there but
not here" failure rather than a repo bug.

- Primary fix: force a clean reinstall of the extension and its deps:
  ```sh
  az extension remove -n ssh
  az extension add -n ssh
  ```
- Fallback if it persists: reinstall `rpds-py` into the CLI's **own** interpreter (Homebrew
  bundles its own Python, so system `pip` is the wrong one), or reinstall the CLI:
  ```sh
  "$(brew --prefix azure-cli)/libexec/bin/python" -m pip install --force-reinstall rpds-py
  # or, nuclear: brew uninstall azure-cli && brew install azure-cli && az extension add -n ssh
  ```
- Symptom is a Python import traceback at session open, not a JIT/network timeout -- if
  JIT reported success and the error is an import error, it is this, not access.

## az CLI surface drift

Flags and output shapes vary between `az` versions. Before relying on a flag
(`az ssh config`, `az ssh vm`, `az rest`, `az vm show -d --query ...`), confirm it
against the installed CLI's `--help`. Pin assumptions to verified behavior, not
memory.
