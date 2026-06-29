#!/usr/bin/env bash
# =============================================================================
# azure-dev-terminal -- stop.sh  (macOS / Linux)
# -----------------------------------------------------------------------------
# Deallocate the dev VM on demand: compute cost stops, the OS disk and your data
# are preserved. Restart any time with connect.sh (which starts the VM, requests
# JIT, and opens a session). This is the cheap, reversible "pause" -- distinct
# from teardown.sh, which DELETES the resource group.
#
# Especially relevant for the dedicated/heavy profile, which is too costly to
# leave running 24/7; deallocate it between sessions rather than waiting for the
# daily auto-shutdown backstop.
#
# Deallocate is immediate (no prompt) and idempotent (a no-op if already stopped).
#
# Usage:  ./stop.sh [config-file]      # defaults to vm.lean.conf
#   e.g.  ./stop.sh                    # RG/VM identical across profiles
#         ./stop.sh vm.heavy.conf
# =============================================================================
set -euo pipefail

ADT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/jit.sh
. "$ADT_DIR/lib/jit.sh"

ADT_CONFIG="${1:-${ADT_CONFIG:-vm.lean.conf}}"
export ADT_CONFIG

adt_require_az
adt_load_config
adt_stop_vm
adt_log "VM '$VM' deallocated. Restart with: ./connect.sh"
