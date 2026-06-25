#!/usr/bin/env bash
# =============================================================================
# azure-dev-terminal -- sync.sh  (macOS / Linux)
# -----------------------------------------------------------------------------
# One-way rsync of a file OR directory between this machine and the dev VM, over
# Microsoft Entra ID SSH. Run it on demand in a separate terminal; it does not
# disturb an open connect.sh session.
#
#   ./sync.sh push <local-path> <remote-dir> [profile] [--delete] [--dry-run]   # local -> VM
#   ./sync.sh pull <remote-path> <local-dir> [profile] [--delete] [--dry-run]   # VM    -> local
#
# Arguments are scp-style: always <source> then <destination>. The SOURCE may be a
# file or a directory; the DESTINATION is the PARENT directory it lands in (created
# if missing). The source basename is preserved, like 'cp' / 'scp':
#   ./sync.sh push ~/notes      /home/you   # -> /home/you/notes/...
#   ./sync.sh push ~/notes.md   /home/you   # -> /home/you/notes.md
#   ./sync.sh pull /home/you/out ./downloads  # -> ./downloads/out/...
#
# Access: if port 22 is already open (connect.sh running / JIT live) it syncs
# immediately; otherwise it requests JIT itself (same logic + profiles as connect.sh),
# waits, then syncs. Transport is a short-lived Entra SSH cert via 'az ssh config';
# no tunnel is created. Files are owned by your Entra login user on the VM.
# =============================================================================
set -euo pipefail

ADT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/jit.sh
. "$ADT_DIR/lib/jit.sh"

usage() {
  echo "Usage (scp-style: <source> then <destination>):" >&2
  echo "  ./sync.sh push <local-path> <remote-dir> [profile] [--delete] [--dry-run]   # local -> VM" >&2
  echo "  ./sync.sh pull <remote-path> <local-dir> [profile] [--delete] [--dry-run]   # VM    -> local" >&2
  exit 1
}

# --- Parse args: direction, then <source> <destination> (scp order), then options ---
DIRECTION="${1:-}"
case "$DIRECTION" in push|pull) ;; *) usage ;; esac
SRC_ARG="${2:-}"
DST_ARG="${3:-}"
[ -n "$SRC_ARG" ] && [ -n "$DST_ARG" ] || usage
case "$SRC_ARG" in -*) usage ;; esac
case "$DST_ARG" in -*) usage ;; esac
shift 3

PROFILE=""; DELETE=""; DRYRUN=""
for arg in "$@"; do
  case "$arg" in
    --delete)  DELETE="--delete" ;;
    --dry-run) DRYRUN="--dry-run" ;;
    -*)        adt_err "unknown option: $arg"; usage ;;
    *)         PROFILE="$arg" ;;
  esac
done

# Map the scp-style source/destination onto local vs remote by direction.
if [ "$DIRECTION" = "push" ]; then
  LOCAL_PATH="$SRC_ARG"; REMOTE_PATH="$DST_ARG"
  [ -e "$LOCAL_PATH" ] || { adt_err "local source does not exist: $LOCAL_PATH"; exit 1; }
else
  REMOTE_PATH="$SRC_ARG"; LOCAL_PATH="$DST_ARG"
fi

adt_require_az
adt_load_config
adt_ensure_access "$PROFILE" "${JIT_DURATION:-PT3H}"

# --- Build a short-lived Entra SSH config for rsync's transport ---
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
CFG="$WORK/config"
az ssh config -g "$RG" -n "$VM" --file "$CFG" --keys-dest-folder "$WORK" --overwrite -o none
HOST_ALIAS="$(awk '/^Host /{for(i=2;i<=NF;i++) if($i!="*"){print $i; exit}}' "$CFG")"
[ -n "$HOST_ALIAS" ] || { adt_err "could not parse Host from generated ssh config."; exit 1; }

# accept-new + a throwaway known_hosts avoids any interactive host-key prompt that
# would hang a non-interactive rsync.
SSH_CMD="ssh -F $CFG -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=$WORK/known_hosts"

# No trailing slash on the source: rsync then places the source (file or dir) by
# basename UNDER the destination directory, matching cp/scp semantics.
SRC_CLEAN="${LOCAL_PATH%/}"
RSYNC_OPTS=(-a -v --exclude '.DS_Store')
[ -n "$DELETE" ] && RSYNC_OPTS+=("$DELETE")
[ -n "$DRYRUN" ] && RSYNC_OPTS+=("$DRYRUN")

if [ "$DIRECTION" = "push" ]; then
  DST_REMOTE="${REMOTE_PATH%/}/"
  adt_log "PUSH  $SRC_CLEAN  ->  ${HOST_ALIAS}:$DST_REMOTE"
  $SSH_CMD "$HOST_ALIAS" "mkdir -p '$DST_REMOTE'"
  rsync "${RSYNC_OPTS[@]}" -e "$SSH_CMD" "$SRC_CLEAN" "${HOST_ALIAS}:$DST_REMOTE"
else
  SRC_REMOTE="${REMOTE_PATH%/}"
  DST_LOCAL="${LOCAL_PATH%/}/"
  adt_log "PULL  ${HOST_ALIAS}:$SRC_REMOTE  ->  $DST_LOCAL"
  mkdir -p "$DST_LOCAL"
  rsync "${RSYNC_OPTS[@]}" -e "$SSH_CMD" "${HOST_ALIAS}:$SRC_REMOTE" "$DST_LOCAL"
fi

adt_log "Done."
