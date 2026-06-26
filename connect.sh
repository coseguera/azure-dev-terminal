#!/usr/bin/env bash
# =============================================================================
# azure-dev-terminal -- connect.sh  (macOS / Linux)
# -----------------------------------------------------------------------------
# Connect to the dev VM over Microsoft Entra ID SSH with Just-in-Time access:
#   1. Start the VM if it is deallocated.
#   2. Request JIT access for port 22 from this machine's source (auto-closes).
#   3. Open an Entra ID SSH session (ephemeral certificate). No VNC, no tunnel.
#
# Uses only the Azure CLI + portable primitives. JIT opens port 22 to your current
# source on request and closes it automatically; there is no standing allow rule.
#
# Usage:  ./connect.sh [-p <network-profile>] [--dev [path]]
#   ./connect.sh                       # shell; JIT source = detected public IP (/32)
#   ./connect.sh -p nat                # shell; JIT source = CIDRs from connect.nat.local
#   ./connect.sh --dev                 # land in nvim at your VM home
#   ./connect.sh --dev dev/proj        # land in nvim at ~/dev/proj on the VM (path is remote)
#   ./connect.sh -p nat --dev dev/proj # combine a network profile with dev mode
#
# NOTE: the dev-mode path is evaluated ON THE VM. Do NOT use '~' or a leading '/Users'
# or '/home' from your client - your local shell expands those to a LOCAL path before
# the helper runs. Pass a path relative to your VM home (e.g. 'dev/proj') or an absolute
# VM path (e.g. '/home/you/dev/proj').
#
# For networks behind a multi-range NAT pool (the detected /32 never matches), create
# a profile once:  echo 'JIT_SRC=203.0.113.0/24,198.51.100.0/24' > connect.nat.local
#
# Dev mode (--dev) opens nvim on the VM in the given directory. Requires a pseudo-tty,
# which `az ssh vm -- -t` allocates.
#
# VM identity (LOC/RG/VM) is read from the VM config; override with ADT_CONFIG.
# =============================================================================
set -euo pipefail

ADT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/jit.sh
. "$ADT_DIR/lib/jit.sh"

usage() {
  cat >&2 <<'USAGE'
Usage: ./connect.sh [-p <network-profile>] [--dev [path]]
  ./connect.sh                       # shell; JIT source = detected public IP (/32)
  ./connect.sh -p nat                # shell; JIT source = CIDRs from connect.nat.local
  ./connect.sh --dev                 # land in nvim at your VM home
  ./connect.sh --dev dev/proj        # land in nvim at ~/dev/proj on the VM (path is remote)
  ./connect.sh -p nat --dev dev/proj # combine a network profile with dev mode

The --dev path is evaluated ON THE VM. Do not use '~' (your local shell expands it
to a local path); pass a path relative to your VM home, or an absolute VM path.
USAGE
}

PROFILE=""
DEV=0
DEV_PATH=""
while [ $# -gt 0 ]; do
  case "$1" in
    -p|--profile)
      [ $# -ge 2 ] || { adt_err "$1 requires a value"; exit 1; }
      PROFILE="$2"; shift 2 ;;
    --dev)
      DEV=1
      # Optional path: consume the next token only if it is not another option.
      if [ $# -ge 2 ] && [ "${2#-}" = "$2" ]; then DEV_PATH="$2"; shift 2; else shift; fi ;;
    -h|--help) usage; exit 0 ;;
    *) adt_err "unknown argument: $1"; usage; exit 1 ;;
  esac
done

adt_require_az
adt_load_config
adt_ensure_access "$PROFILE" "${JIT_DURATION:-PT3H}"

if [ "$DEV" = "1" ]; then
  # Build the remote command: open nvim (in $path if given).
  if [ -z "$DEV_PATH" ] || [ "$DEV_PATH" = "~" ]; then
    remote_cmd='nvim'
  else
    # Single-quote the path for the remote shell, escaping any embedded single quotes.
    q="$(printf "%s" "$DEV_PATH" | sed "s/'/'\\\\''/g")"
    remote_cmd="cd '$q' && nvim ."
  fi
  adt_log "Opening Entra ID SSH session to $VM (dev mode: nvim) ..."
  exec az ssh vm -g "$RG" -n "$VM" -- -t "$remote_cmd"
fi

adt_log "Opening Entra ID SSH session to $VM ..."
exec az ssh vm -g "$RG" -n "$VM"
