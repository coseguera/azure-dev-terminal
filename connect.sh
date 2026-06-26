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
# Usage:  ./connect.sh [network-profile]
#   ./connect.sh              # JIT source = this machine's detected public IP (/32)
#   ./connect.sh nat          # JIT source = CIDRs from connect.nat.local (gitignored)
#
# For networks behind a multi-range NAT pool (the detected /32 never matches), create
# a profile once:  echo 'JIT_SRC=203.0.113.0/24,198.51.100.0/24' > connect.nat.local
#
# VM identity (LOC/RG/VM) is read from the VM config; override with ADT_CONFIG.
# =============================================================================
set -euo pipefail

ADT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/jit.sh
. "$ADT_DIR/lib/jit.sh"

PROFILE="${1:-}"

adt_require_az
adt_load_config
adt_ensure_access "$PROFILE" "${JIT_DURATION:-PT3H}"

adt_log "Opening Entra ID SSH session to $VM ..."
exec az ssh vm -g "$RG" -n "$VM"
