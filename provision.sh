#!/usr/bin/env bash
# =============================================================================
# azure-dev-terminal -- provision.sh
# -----------------------------------------------------------------------------
# Stand up a console-first, SSH-only Azure dev VM:
#   - Microsoft Entra ID SSH login (no static key as the primary identity)
#   - Just-in-Time (JIT) network access (port 22 opens on request, then auto-closes)
#     behind a default-deny NSG, instead of a standing inbound rule
#   - Trusted Launch (Secure Boot + vTPM + measured boot)
#
# This script is the ASSEMBLY + ACCESS layer. It renders the thin Azure cloud-init
# overlay (cloud-init/azure/custom-data.example) into a self-contained custom-data
# by substituting:
#   __ADMIN__         -> the admin username
#   __COREBUILD_B64__ -> base64 of the whole core-build/ tree (inlined; no boot-time
#                        repo dependency), which the overlay extracts and runs.
#
# Prereqs: Azure CLI installed and logged in (`az login`) with an active subscription,
#          and permission to enable Defender plans + create role assignments.
#
# Usage:  ./provision.sh [config-file]      # defaults to vm.lean.conf
#   e.g.  ./provision.sh vm.lean.conf       # burstable B2as_v2, always-on (recommended)
#         ./provision.sh vm.heavy.conf      # dedicated D4as_v5, with auto-shutdown
# =============================================================================
set -euo pipefail

cd "$(dirname "$0")"
SCRIPT_DIR="$(pwd)"
OVERLAY="cloud-init/azure/custom-data.example"
COREBUILD_DIR="core-build"
RENDERED="cloud-init/azure/custom-data"   # gitignored; rendered for inspection + az

# ===================== Configuration =====================
CONFIG_FILE="${1:-vm.lean.conf}"
if [ ! -f "$CONFIG_FILE" ]; then
  echo "ERROR: config file not found: $CONFIG_FILE" >&2
  echo "       e.g.:  ./provision.sh vm.lean.conf" >&2
  echo "       (available: $(ls vm.*.conf 2>/dev/null | tr '\n' ' '))" >&2
  exit 1
fi
echo ">> Using configuration: $CONFIG_FILE"
# shellcheck disable=SC1090
case "$CONFIG_FILE" in
  */*) . "$CONFIG_FILE" ;;     # has a path component - source as given
  *)   . "./$CONFIG_FILE" ;;   # bare filename - force CWD (don't search $PATH)
esac

: "${LOC:?set LOC in $CONFIG_FILE}"
: "${RG:?set RG in $CONFIG_FILE}"
: "${VM:?set VM in $CONFIG_FILE}"
: "${ADMIN:?set ADMIN in $CONFIG_FILE}"
: "${IMAGE:?set IMAGE in $CONFIG_FILE}"
: "${SIZE:?set SIZE in $CONFIG_FILE}"
: "${OSDISK_GB:?set OSDISK_GB in $CONFIG_FILE}"
: "${DISK_SKU:?set DISK_SKU in $CONFIG_FILE}"
: "${JIT_MAX_DURATION:?set JIT_MAX_DURATION in $CONFIG_FILE}"
AUTOSHUTDOWN_UTC="${AUTOSHUTDOWN_UTC:-}"   # empty = always-on (no auto-shutdown)
NSG="${VM}-nsg"
# =========================================================

START_TS=$(date +%s)

command -v az  >/dev/null || { echo "ERROR: Azure CLI (az) not found." >&2; exit 1; }
command -v tar >/dev/null || { echo "ERROR: tar not found." >&2; exit 1; }
az account show >/dev/null 2>&1 || { echo "ERROR: run 'az login' first." >&2; exit 1; }
[ -f "$OVERLAY" ]        || { echo "ERROR: overlay not found: $OVERLAY" >&2; exit 1; }
[ -f "$COREBUILD_DIR/install.sh" ] || { echo "ERROR: core-build/install.sh not found (run 'git submodule update --init')." >&2; exit 1; }

SUB="$(az account show --query id -o tsv)"
USER_OID="$(az ad signed-in-user show --query id -o tsv)"
echo ">> Subscription: $SUB"
echo ">> Signed-in user object id: $USER_OID"

# --- Render the self-contained custom-data (inline core-build, inject admin) ---
echo ">> Inlining core-build/ and rendering $RENDERED"
# core-build is a git submodule (dev-machine). Exclude VCS metadata (.git gitfile,
# .gitignore) so the inlined tarball carries only the installer + files/ payload.
COREBUILD_B64="$(tar czf - -C "$COREBUILD_DIR" --exclude='./.git' --exclude='./.gitignore' . | base64 -w0)"
# base64's alphabet (A-Za-z0-9+/=) contains no awk-special chars, so gsub is safe here.
awk -v b64="$COREBUILD_B64" -v admin="$ADMIN" '
  { gsub(/__COREBUILD_B64__/, b64); gsub(/__ADMIN__/, admin); print }
' "$OVERLAY" > "$RENDERED"

# --- Guard: custom-data MUST be pure ASCII (a non-ASCII byte breaks az vm create) ---
if LC_ALL=C grep -qP '[^\x00-\x7F]' "$RENDERED"; then
  echo "ERROR: rendered custom-data contains non-ASCII bytes:" >&2
  LC_ALL=C grep -nP '[^\x00-\x7F]' "$RENDERED" >&2
  exit 1
fi

# --- Throwaway SSH key ---
# Azure requires a credential to create a Linux VM, but we do NOT keep it: generated in
# a temp dir, used only for `az vm create`, then discarded here AND wiped from the VM by
# cloud-init. The only usable login path is Entra ID SSH.
TMP_KEYDIR="$(mktemp -d)"
trap 'rm -rf "$TMP_KEYDIR"' EXIT
THROWAWAY_KEY="$TMP_KEYDIR/throwaway"
ssh-keygen -t ed25519 -f "$THROWAWAY_KEY" -N "" -C "azvm-throwaway-discarded" -q

# --- Resource group ---
echo ">> Creating resource group $RG in $LOC"
az group create -n "$RG" -l "$LOC" -o none

# --- NSG with NO standing inbound SSH rule (JIT manages port 22 on demand) ---
echo ">> Creating NSG $NSG (default-deny inbound; JIT opens 22 on request)"
az network nsg create -g "$RG" -n "$NSG" -l "$LOC" -o none

# --- The VM (system-assigned managed identity required for Entra SSH) ---
echo ">> Creating VM $VM ($SIZE). This takes a few minutes..."
az vm create \
  -g "$RG" -n "$VM" -l "$LOC" \
  --image "$IMAGE" \
  --size "$SIZE" \
  --admin-username "$ADMIN" \
  --ssh-key-values "${THROWAWAY_KEY}.pub" \
  --nsg "$NSG" \
  --public-ip-sku Standard \
  --storage-sku "$DISK_SKU" \
  --os-disk-size-gb "$OSDISK_GB" \
  --assign-identity '[system]' \
  --security-type TrustedLaunch \
  --enable-secure-boot true \
  --enable-vtpm true \
  --custom-data "$RENDERED" \
  -o none

VM_ID="$(az vm show -g "$RG" -n "$VM" --query id -o tsv)"

# --- Entra ID SSH login extension ---
echo ">> Installing Microsoft Entra ID SSH login extension"
az vm extension set \
  -g "$RG" --vm-name "$VM" \
  --name AADSSHLoginForLinux \
  --publisher Microsoft.Azure.ActiveDirectory \
  -o none

# --- RBAC: allow the signed-in user to log in as admin (sudo) via Entra ---
echo ">> Assigning 'Virtual Machine Administrator Login' to you on the VM"
az role assignment create \
  --assignee-object-id "$USER_OID" \
  --assignee-principal-type User \
  --role "Virtual Machine Administrator Login" \
  --scope "$VM_ID" \
  -o none

# --- Entra-only login is enforced by account lockdown (see the cloud-init overlay) ---
# We deliberately do NOT set sshd 'AllowGroups': Entra ID SSH uses DYNAMIC group
# membership that sshd's AllowGroups check does not see, so it would reject every
# legitimate Entra login. Entra-only access is already guaranteed because password auth
# is off, root login is off, and the local admin account is locked with no
# authorized_keys and no sudo. The only credential that can authenticate is the
# Entra-issued certificate.
#
# NOTE: the lean baseline is BURSTABLE + ALWAYS-ON, so the VM never stops itself --
# there is NO VM self-deallocate managed-identity role (dropped by design). Cost control
# for the dedicated/heavy profile is the control-plane auto-shutdown below.

# --- Auto-shutdown (control-plane backstop; dedicated profiles only) ---
if [ -n "$AUTOSHUTDOWN_UTC" ]; then
  echo ">> Enabling daily auto-shutdown at ${AUTOSHUTDOWN_UTC} UTC"
  az vm auto-shutdown -g "$RG" -n "$VM" --time "$AUTOSHUTDOWN_UTC" -o none
else
  echo ">> Auto-shutdown: OFF (always-on; burstable banks credits, fits budget)"
  az vm auto-shutdown -g "$RG" -n "$VM" --off -o none 2>/dev/null || true
fi

# --- Microsoft Defender for Servers (required for JIT; ~\$15/VM/month) ---
echo ""
echo "JIT access requires Microsoft Defender for Servers Plan 2 on this subscription"
echo "(roughly \$15 per server per month)."
read -r -p ">> Enable Defender for Servers Plan 2 now? [y/N] " ANSWER
if [[ "$ANSWER" =~ ^[Yy]$ ]]; then
  az security pricing create -n VirtualMachines --tier standard --subplan P2 -o none
  echo "   Defender for Servers (Plan 2) enabled; waiting for it to propagate..."
  sleep 30
else
  echo "   Skipped. JIT requires Defender for Servers Plan 2 and will fail without it."
fi

# --- JIT network access policy for the VM (port 22) ---
echo ">> Creating Just-in-Time access policy (port 22, max ${JIT_MAX_DURATION})"
JIT_BODY="$(cat <<JSON
{
  "kind": "Basic",
  "location": "$LOC",
  "properties": {
    "virtualMachines": [
      {
        "id": "$VM_ID",
        "ports": [
          {
            "number": 22,
            "protocol": "*",
            "allowedSourceAddressPrefix": "*",
            "maxRequestAccessDuration": "$JIT_MAX_DURATION"
          }
        ]
      }
    ]
  }
}
JSON
)"
JIT_URL="https://management.azure.com/subscriptions/${SUB}/resourceGroups/${RG}/providers/Microsoft.Security/locations/${LOC}/jitNetworkAccessPolicies/default?api-version=2020-01-01"

# Defender can take a few minutes to propagate after being enabled; retry the PUT.
JIT_OK=""
for attempt in 1 2 3 4 5 6 7 8; do
  if az rest --method put --url "$JIT_URL" --body "$JIT_BODY" -o none 2>/tmp/jit_err; then
    JIT_OK="yes"; break
  fi
  echo "   JIT policy not ready yet (attempt $attempt/8): $(tr -d '\n' </tmp/jit_err | tail -c 160)"
  sleep 30
done
rm -f /tmp/jit_err
if [ -z "$JIT_OK" ]; then
  echo "ERROR: Could not create the JIT policy after several attempts." >&2
  echo "       Ensure Defender for Servers Plan 2 is active, then re-run provision.sh." >&2
  exit 1
fi
echo "   JIT policy created."

IP="$(az vm show -g "$RG" -n "$VM" -d --query publicIps -o tsv)"
ELAPSED=$(( $(date +%s) - START_TS ))
echo ""
echo "========================================================"
echo " VM ready.  Public IP: $IP   (port 22 stays CLOSED until you request JIT)"
echo " Core build (cloud-init) finishes a few minutes after boot."
echo ""
echo " Provisioning took:  $(printf '%dm %02ds' $((ELAPSED/60)) $((ELAPSED%60)))"
echo " Finished at:        $(date '+%Y-%m-%d %H:%M:%S %Z')"
echo ""
echo " Connect with:     ./connect.sh"
echo " Login:            Entra ID only (az ssh). The local '$ADMIN' account cannot SSH in."
echo "========================================================"
