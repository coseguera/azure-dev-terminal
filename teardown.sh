#!/usr/bin/env bash
# =============================================================================
# azure-dev-terminal -- teardown.sh
# -----------------------------------------------------------------------------
# Cleanly reverse everything provision.sh creates or modifies:
#   - the resource group (VM, NSG, NIC, public IP, OS disk, AAD SSH extension,
#     auto-shutdown schedule, and the RG-scoped JIT network access policy)
#   - the VM-scoped "Virtual Machine Administrator Login" role assignment
#   - (optionally) Microsoft Defender for Servers Plan 2, which is SUBSCRIPTION-WIDE
#   - the local rendered (gitignored) cloud-init custom-data artifact
#
# Deleting the resource group is IRREVERSIBLE, so this requires you to type the
# resource group name to confirm.
#
# Prereqs: Azure CLI installed and logged in (`az login`) with an active subscription.
#
# Usage:  ./teardown.sh [config-file]      # defaults to vm.lean.conf
#   e.g.  ./teardown.sh vm.lean.conf
#         ./teardown.sh vm.heavy.conf
# =============================================================================
set -euo pipefail

cd "$(dirname "$0")"
RENDERED="cloud-init/azure/custom-data"   # gitignored; produced by provision.sh

# ===================== Configuration =====================
CONFIG_FILE="${1:-vm.lean.conf}"
if [ ! -f "$CONFIG_FILE" ]; then
  echo "ERROR: config file not found: $CONFIG_FILE" >&2
  echo "       e.g.:  ./teardown.sh vm.lean.conf" >&2
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
# =========================================================

command -v az >/dev/null || { echo "ERROR: Azure CLI (az) not found." >&2; exit 1; }
az account show >/dev/null 2>&1 || { echo "ERROR: run 'az login' first." >&2; exit 1; }

if ! az group show -n "$RG" >/dev/null 2>&1; then
  echo ">> Resource group '$RG' does not exist; nothing to delete."
  echo "   (You may still want to check Defender for Servers below.)"
fi

SUB="$(az account show --query id -o tsv)"
# Resolve the signed-in user and VM id BEST-EFFORT: the VM may already be gone, and the
# role assignment delete just becomes a no-op in that case.
USER_OID="$(az ad signed-in-user show --query id -o tsv 2>/dev/null || true)"
VM_ID="$(az vm show -g "$RG" -n "$VM" --query id -o tsv 2>/dev/null || true)"

echo ""
echo "========================================================"
echo " TEARDOWN -- this will DELETE the following:"
echo "   - Resource group:   $RG   (in $LOC)"
echo "       includes VM '$VM', NSG, NIC, public IP, OS disk,"
echo "       AAD SSH extension, auto-shutdown schedule, JIT policy"
echo "   - Role assignment:  'Virtual Machine Administrator Login' on the VM"
echo "   - Local artifact:   $RENDERED (if present)"
echo " Defender for Servers Plan 2 (subscription-wide) is handled separately below."
echo "========================================================"
echo ""
echo " This is IRREVERSIBLE. To confirm, type the resource group name exactly."
read -r -p ">> Type '$RG' to delete, or anything else to abort: " CONFIRM
if [ "$CONFIRM" != "$RG" ]; then
  echo ">> Confirmation did not match. Aborted; nothing was deleted."
  exit 1
fi

# --- Best-effort: remove the VM-scoped role assignment ---
# (Deleting the VM would orphan it anyway, but we clean it up explicitly.)
if [ -n "$USER_OID" ] && [ -n "$VM_ID" ]; then
  echo ">> Removing 'Virtual Machine Administrator Login' role assignment"
  az role assignment delete \
    --assignee-object-id "$USER_OID" \
    --role "Virtual Machine Administrator Login" \
    --scope "$VM_ID" \
    -o none 2>/dev/null || echo "   (no matching role assignment, or already removed)"
else
  echo ">> Skipping role assignment cleanup (VM or signed-in user not resolved)"
fi

# --- Best-effort: delete the JIT network access policy (also covered by RG delete) ---
echo ">> Deleting Just-in-Time access policy (if present)"
JIT_URL="https://management.azure.com/subscriptions/${SUB}/resourceGroups/${RG}/providers/Microsoft.Security/locations/${LOC}/jitNetworkAccessPolicies/default?api-version=2020-01-01"
az rest --method delete --url "$JIT_URL" -o none 2>/dev/null || echo "   (no JIT policy, or already removed)"

# --- Delete the resource group (waits so you see it finish) ---
if az group show -n "$RG" >/dev/null 2>&1; then
  echo ">> Deleting resource group $RG (this takes a few minutes)..."
  az group delete -n "$RG" --yes -o none
  echo "   Resource group deleted."
else
  echo ">> Resource group $RG already absent; skipping."
fi

# --- Defender for Servers Plan 2 (SUBSCRIPTION-WIDE) ---
echo ""
echo "Microsoft Defender for Servers Plan 2 is enabled per SUBSCRIPTION, not per VM."
echo "Disabling it affects EVERY server in this subscription (and may reduce protection"
echo "and JIT for other VMs). Only disable it if this VM was the reason it was on."
read -r -p ">> Disable Defender for Servers Plan 2 subscription-wide now? [y/N] " ANSWER
if [[ "$ANSWER" =~ ^[Yy]$ ]]; then
  az security pricing create -n VirtualMachines --tier free -o none
  echo "   Defender for Servers set to the free tier."
else
  echo "   Left Defender for Servers unchanged."
fi

# --- Best-effort: remove the local rendered custom-data artifact ---
if [ -f "$RENDERED" ]; then
  echo ">> Removing local rendered artifact: $RENDERED"
  rm -f "$RENDERED"
fi

echo ""
echo "========================================================"
echo " Teardown complete."
echo " Re-create anytime with:  ./provision.sh $CONFIG_FILE"
echo "========================================================"
