# Running commands on the VM (for validation/automation)

How to run **one-off, non-interactive** commands on the dev VM -- the technique used
to validate a freshly provisioned box (assert tools are present, read logs, push a
file) without sitting in an interactive shell. It reuses the same Entra ID SSH +
JIT machinery as `connect.sh`; it just separates "get me a credential" from "run
this command" so the result is scriptable.

## The two modes

| | Interactive (`connect.sh`) | Non-interactive (this doc) |
|---|---|---|
| Command | `az ssh vm` (ends in `exec`) | `az ssh config` + plain `ssh` |
| Behavior | drops *you* at a shell prompt (blocks) | runs one command, prints output, exits |
| Captures output of a single command | hard | easy |
| Scriptable / loopable | no | yes |
| Credential | ephemeral Entra cert | same ephemeral Entra cert |
| Network access | JIT via `lib/jit.sh` | JIT via the **same** `lib/jit.sh` |

Same identity, same JIT, same security posture. The only difference is that
`az ssh vm` couples connect+run, while `az ssh config` emits a reusable transport
(cert + key + OpenSSH config) that you drive with your own `ssh`/`scp`/`rsync`.

## Quick one-liner

`az ssh vm` accepts a trailing command after `--`, which is enough for a quick
check:

```sh
az ssh vm -g "$RG" -n "$VM" -- "nvim --version; node --version; which copilot lazygit"
```

(You still need port 22 open first -- run `./connect.sh` once, or the
`adt_ensure_access` step below.)

## The reusable-transport recipe

Use this when you want to run many commands, or reuse the connection for
`scp`/`rsync` (this is exactly what `sync.sh` does).

### 1. Open the network (reuse the shared lib)

```sh
. lib/jit.sh
adt_require_az
adt_load_config
adt_ensure_access "$PROFILE"     # opens JIT for port 22, or reuses a live window
```

`adt_ensure_access` is the same function `connect.sh` and `sync.sh` call -- it
checks whether port 22 is already reachable and only requests a new JIT window if
not. `$PROFILE` is empty for your detected `/32`, or a network-profile name (e.g.
`nat`) for a multi-range NAT pool.

### 2. Generate a short-lived cert + config

```sh
mkdir -p /tmp/adt-ssh
az ssh config --resource-group "$RG" --name "$VM" \
  --file /tmp/adt-ssh/config \
  --keys-dest-folder /tmp/adt-ssh/keys \
  --overwrite
```

`az ssh config` writes an OpenSSH `config` file containing a `Host` alias whose
`IdentityFile` / `CertificateFile` point at a freshly minted ephemeral key+cert in
`--keys-dest-folder`. The certificate is short-lived (about an hour).

### 3. Parse the `Host` alias

```sh
alias=$(awk '/^Host /{print $2; exit}' /tmp/adt-ssh/config)
```

### 4. Run any command non-interactively

```sh
ssh -F /tmp/adt-ssh/config \
  -o StrictHostKeyChecking=accept-new \
  -o UserKnownHostsFile=/tmp/adt-ssh/known_hosts \
  "$alias" "nvim --version; node --version; which copilot lazygit"
```

Because a command string is passed, `ssh` executes it, streams stdout/stderr back,
and exits with the **remote** command's exit code -- so you can assert success in a
script. `StrictHostKeyChecking=accept-new` plus a temp `UserKnownHostsFile` avoid an
interactive host-key prompt on a fresh VM without permanently trusting the host.

### Pushing a file over the same transport

No extra tooling needed -- pipe a tar over `ssh`:

```sh
tar czf - -C localdir . | ssh -F /tmp/adt-ssh/config "$alias" \
  "mkdir -p ~/dest && tar xzf - -C ~/dest"
```

(`sync.sh` / `sync.ps1` do the polished version of this with `rsync` over the same
`az ssh config` transport.)

## Notes

- **Clean up** the temp dir when done (`rm -rf /tmp/adt-ssh`); it holds a private key
  and a valid-for-now certificate.
- The JIT window auto-closes after its duration; nothing leaves a standing inbound
  rule.
- This is a **client-side** technique -- it adds nothing to the VM and changes no
  committed helper. It just composes `az ssh config` + `ssh` the way `sync.sh`
  already does internally.
