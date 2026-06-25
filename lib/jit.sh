#!/usr/bin/env bash
# =============================================================================
# azure-dev-terminal -- lib/jit.sh
# -----------------------------------------------------------------------------
# Shared helpers for Entra ID SSH + Just-in-Time (JIT) access. Sourced by both
# connect.sh and sync.sh so the JIT / CIDR-source logic lives in ONE place.
#
# Provides:
#   adt_require_az            - verify az is installed, logged in, ssh ext present
#   adt_load_config           - source the VM config (LOC/RG/VM); set SUB, VM_ID
#   adt_resolve_src [profile] - set SRC + PREFIX_JSON (detected /32 or CIDR profile)
#   adt_start_vm              - start the VM if it is deallocated
#   adt_request_jit [dur]     - request JIT access (port 22) for SRC
#
# These functions print progress to stderr so callers can still capture stdout.
# =============================================================================

# Directory of the script that sourced this lib (for locating config + profiles).
ADT_DIR="${ADT_DIR:-$(cd "$(dirname "${BASH_SOURCE[1]:-$0}")" && pwd)}"

adt_log() { echo ">> $*" >&2; }
adt_err() { echo "ERROR: $*" >&2; }

adt_require_az() {
  command -v az >/dev/null || { adt_err "Azure CLI (az) not found."; return 1; }
  az account show >/dev/null 2>&1 || { adt_err "run 'az login' first."; return 1; }
  # Pre-install the 'ssh' extension non-interactively so connecting doesn't pause.
  az extension show -n ssh >/dev/null 2>&1 || az extension add -n ssh -y -o none
}

# Source the VM config for LOC/RG/VM, then resolve SUB and VM_ID from Azure.
# Override which config to read with ADT_CONFIG (defaults to vm.lean.conf); RG/VM/LOC
# are identical across the shipped profiles, so the lean file is a fine default.
adt_load_config() {
  local cfg="${ADT_CONFIG:-vm.lean.conf}"
  local cfg_path="$cfg"
  [ -f "$cfg_path" ] || cfg_path="$ADT_DIR/$cfg"
  [ -f "$cfg_path" ] || { adt_err "VM config not found: $cfg (set ADT_CONFIG)"; return 1; }
  # shellcheck disable=SC1090
  . "$cfg_path"
  : "${LOC:?set LOC in $cfg}"
  : "${RG:?set RG in $cfg}"
  : "${VM:?set VM in $cfg}"
  SUB="$(az account show --query id -o tsv)"
  VM_ID="$(az vm show -g "$RG" -n "$VM" --query id -o tsv)"
  [ -n "$VM_ID" ] || { adt_err "could not resolve VM id for $VM in $RG"; return 1; }
}

# Resolve the JIT source range(s). With no profile: this machine's detected public IP
# (a /32). With a profile name: the CIDR list from connect.<name>.local (gitignored).
# Sets SRC (human string) and PREFIX_JSON (a JSON array body of quoted prefixes).
adt_resolve_src() {
  local profile="${1:-}"
  local src=""
  if [ -n "$profile" ]; then
    local pf="$ADT_DIR/connect.$profile.local"
    [ -f "$pf" ] || {
      adt_err "network profile not found: $pf"
      adt_err "create it with: echo 'JIT_SRC=<cidr>[,<cidr>...]' > $(basename "$pf")"
      return 1
    }
    # shellcheck disable=SC1090
    . "$pf"
    adt_log "Using network profile: $profile"
  fi
  if [ -n "${JIT_SRC:-}" ]; then
    src="$JIT_SRC"
  else
    src="$(curl -fsS https://api.ipify.org)" || { adt_err "could not detect public IP"; return 1; }
  fi
  SRC="$src"
  # Build a JSON array of source prefixes from the comma-separated SRC (trims spaces).
  PREFIX_JSON="$(printf '%s' "$src" | awk -F, '{for(i=1;i<=NF;i++){gsub(/^[ \t]+|[ \t]+$/,"",$i); printf "%s\"%s\"",(i>1?",":""),$i}}')"
}

adt_start_vm() {
  adt_log "Ensuring VM is running..."
  az vm start -g "$RG" -n "$VM" -o none || true
}

# Request JIT access for port 22 from SRC. Arg 1 = duration (ISO 8601, default PT3H).
adt_request_jit() {
  local duration="${1:-PT3H}"
  adt_log "Requesting JIT access (port 22) for source(s): $SRC"
  local body
  body="$(cat <<JSON
{
  "virtualMachines": [
    {
      "id": "$VM_ID",
      "ports": [
        { "number": 22, "duration": "$duration", "allowedSourceAddressPrefixes": [ $PREFIX_JSON ] }
      ]
    }
  ],
  "justification": "interactive dev session"
}
JSON
)"
  az rest --method post \
    --url "https://management.azure.com/subscriptions/${SUB}/resourceGroups/${RG}/providers/Microsoft.Security/locations/${LOC}/jitNetworkAccessPolicies/default/initiate?api-version=2020-01-01" \
    --body "$body" -o none
  adt_log "Waiting for the access rule to take effect..."
  sleep 12
}
