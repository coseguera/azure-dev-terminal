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
#   __COREBUILD_B64__ -> base64 of the whole dev-machine core build tree (inlined; no
#                        boot-time repo dependency), which the overlay extracts and runs.
#
# The core build (dev-machine repo) is a plain local clone, NOT a submodule. It lives
# at --dev-machine-dir (default ./dev-machine, gitignored). If that directory is missing,
# this script offers to `git clone` it. Whatever is on disk (your edits / branch) is what
# gets deployed -- it is never auto-pulled.
#
# Prereqs: Azure CLI installed and logged in (`az login`) with an active subscription,
#          and permission to enable Defender plans + create role assignments.
#
# Usage:  ./provision.sh [config-file] [--dev-machine-dir DIR] [--yes]
#   e.g.  ./provision.sh vm.lean.conf                 # burstable B2as_v2, always-on (recommended)
#         ./provision.sh vm.heavy.conf                # dedicated D4as_v5, with auto-shutdown
#         ./provision.sh --dev-machine-dir ../dm      # use an existing dev-machine checkout
#         ./provision.sh vm.lean.conf --yes           # skip the interactive confirmations
# =============================================================================
set -euo pipefail

cd "$(dirname "$0")"
SCRIPT_DIR="$(pwd)"
OVERLAY="cloud-init/azure/custom-data.example"
RENDERED="cloud-init/azure/custom-data"   # gitignored; rendered for inspection + az

# dev-machine core build source: a plain local clone (not a submodule). Default
# location; override with --dev-machine-dir. Cloned on demand if missing.
DEVMACHINE_DIR="dev-machine"
DEVMACHINE_URL="https://github.com/coseguera/dev-machine.git"
ASSUME_YES=0

# confirm "message" -> 0 if the user (or --yes) approves, non-zero otherwise. Reads
# from the controlling terminal so it works even when stdin is redirected; with no
# TTY available it declines (fail-loud rather than silently assuming yes).
confirm() {
  local prompt="$1" reply
  [ "$ASSUME_YES" -eq 1 ] && return 0
  if ! { : >/dev/tty; } 2>/dev/null; then
    echo "ERROR: no TTY available to confirm: $prompt (re-run with --yes to auto-approve)" >&2
    return 1
  fi
  printf '%s [y/N] ' "$prompt" > /dev/tty
  read -r reply < /dev/tty || reply=""
  case "$reply" in [yY]|[yY][eE][sS]) return 0 ;; *) return 1 ;; esac
}

# ===================== Argument parsing =====================
CONFIG_FILE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dev-machine-dir)   shift; DEVMACHINE_DIR="${1:?--dev-machine-dir needs a path}" ;;
    --dev-machine-dir=*) DEVMACHINE_DIR="${1#*=}" ;;
    -y|--yes)            ASSUME_YES=1 ;;
    -h|--help)
      sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    -*) echo "ERROR: unknown option: $1" >&2; exit 1 ;;
    *)  if [ -z "$CONFIG_FILE" ]; then CONFIG_FILE="$1"
        else echo "ERROR: unexpected extra argument: $1" >&2; exit 1; fi ;;
  esac
  shift
done
CONFIG_FILE="${CONFIG_FILE:-vm.lean.conf}"
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

# --- Ensure the dev-machine core build is present (clone on demand) ---
if [ ! -f "$DEVMACHINE_DIR/install.sh" ]; then
  echo ">> dev-machine core build not found at '$DEVMACHINE_DIR'"
  if confirm "Clone dev-machine from $DEVMACHINE_URL into '$DEVMACHINE_DIR'?"; then
    command -v git >/dev/null || { echo "ERROR: git not found (needed to clone dev-machine)." >&2; exit 1; }
    git clone "$DEVMACHINE_URL" "$DEVMACHINE_DIR"
  else
    echo "ERROR: dev-machine core build required at '$DEVMACHINE_DIR' (install.sh missing)." >&2
    exit 1
  fi
fi
[ -f "$DEVMACHINE_DIR/install.sh" ] || { echo "ERROR: '$DEVMACHINE_DIR/install.sh' still missing after clone." >&2; exit 1; }

# --- Report exactly what core build is being deployed (ref/commit/dirty) ---
DM_DIRTY=""
if git -C "$DEVMACHINE_DIR" rev-parse --git-dir >/dev/null 2>&1; then
  DM_REF="$(git -C "$DEVMACHINE_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
  DM_SHA="$(git -C "$DEVMACHINE_DIR" rev-parse --short HEAD 2>/dev/null || echo '?')"
  [ -n "$(git -C "$DEVMACHINE_DIR" status --porcelain 2>/dev/null)" ] && DM_DIRTY=" (dirty)"
  echo ">> dev-machine: $DEVMACHINE_DIR @ $DM_REF ($DM_SHA)$DM_DIRTY"
else
  DM_REF="n/a"; DM_SHA="n/a"
  echo ">> dev-machine: $DEVMACHINE_DIR (not a git repo -- using files as-is)"
fi

SUB="$(az account show --query id -o tsv)"
USER_OID="$(az ad signed-in-user show --query id -o tsv)"
echo ">> Subscription: $SUB"
echo ">> Signed-in user object id: $USER_OID"

# --- Render the self-contained custom-data (inline dev-machine, inject admin) ---
echo ">> Inlining '$DEVMACHINE_DIR' and rendering $RENDERED"
# The dev-machine core build is a plain local clone. Exclude VCS metadata (.git
# gitfile/dir, .gitignore) so the inlined tarball carries only the installer + files/.
COREBUILD_B64="$(tar czf - -C "$DEVMACHINE_DIR" --exclude='./.git' --exclude='./.gitignore' . | base64 -w0)"
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

# --- Final confirmation before creating any Azure resources ---
cat <<EOF

About to provision:
  VM:           $VM ($SIZE)
  Resource grp: $RG
  Location:     $LOC
  Admin user:   $ADMIN
  dev-machine:  $DEVMACHINE_DIR @ $DM_REF ($DM_SHA)$DM_DIRTY
  custom-data:  $RENDERED

EOF
confirm "Proceed with provisioning (creates Azure resources)?" \
  || { echo "Aborted before creating any Azure resources."; exit 0; }

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
