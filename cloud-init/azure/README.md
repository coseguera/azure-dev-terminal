# cloud-init/azure

The **thin Azure/Entra overlay**. `custom-data.example` is the committed template
for the Azure `--custom-data` config. It does only platform-specific work and then
runs the platform-agnostic core build (the local `dev-machine` clone); it does **not** contain
the toolchain/dotfiles logic.

## What the overlay does

- Hardens the host: SSH (no passwords/root/X11), `ufw`, `unattended-upgrades`.
- Extracts and runs the **inlined core build** (`install.sh --target-dir /etc/skel`).
- Locks the local admin account (`__ADMIN__`) out of SSH and sudo.

## Account model

This VM is reached purely over **Microsoft Entra ID SSH**. On first login your home
is created from `/etc/skel` (via `pam_mkhomedir`), so you land directly in a ready
LazyVim + Copilot CLI environment **as your Entra identity** -- there is no fixed dev
account. The admin account from `az vm create` is locked down at the end.

## Rendering (provision.sh)

`provision.sh` renders a filled copy named `custom-data` (gitignored) by substituting:

| Placeholder | Substituted with |
|---|---|
| `__ADMIN__` | the `az vm create --admin-username` value (locked out at the end) |
| `__COREBUILD_B64__` | `tar czf - -C <dev-machine-dir> . \| base64 -w0` -- the whole dev-machine core build tree, inlined so the deployed config is self-contained (no boot-time repo dependency). `<dev-machine-dir>` defaults to `./dev-machine` (a local clone, not a submodule). |

## Constraints

- **Pure ASCII only.** A non-ASCII byte breaks `az vm create`. Verify:
  `LC_ALL=C grep -n "[^$(printf '\01-\177')]" custom-data.example`
- **Idempotent** where practical; "reset" = delete + recreate the VM.
- The VM installs **no fonts** -- glyphs/theme render in the client terminal.

## Validate locally

```sh
LC_ALL=C grep -n "[^$(printf '\01-\177')]" custom-data.example   # must print nothing

# schema-check a rendered copy (real b64 + admin substituted):
B64="$(tar czf - -C ../../dev-machine . | base64 -w0)"
python3 - "$B64" <<'PY'
import sys
t=open('custom-data.example').read()
t=t.replace('__COREBUILD_B64__',sys.argv[1]).replace('__ADMIN__','azureuser')
open('/tmp/rendered','w').write(t)
PY
cloud-init schema --config-file /tmp/rendered   # expect "Valid schema"
```
