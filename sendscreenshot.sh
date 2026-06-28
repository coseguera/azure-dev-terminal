#!/usr/bin/env bash
# =============================================================================
# azure-dev-terminal -- sendscreenshot.sh  (macOS / Linux)
# -----------------------------------------------------------------------------
# Upload a screenshot that is ALREADY on your local clipboard to a directory on
# the dev VM, then print the VM path so you can @-mention it in the Copilot CLI.
#
#   ./sendscreenshot.sh <remote-dir> [-p <profile>]
#
# Example:
#   # take a screenshot to the clipboard (macOS: Cmd+Ctrl+Shift+4), then:
#   ./sendscreenshot.sh dev/shots
#   # -> uploads dev/shots/screenshot-YYYYmmdd-HHMMSS.png on the VM
#
# It proceeds ONLY if the clipboard holds bitmap IMAGE data; copied text or a
# copied FILE reference is refused so nothing is sent by accident. The clipboard
# is left untouched. Transport reuses sync.sh (Entra ID SSH cert + rsync + JIT),
# so the same network profiles apply.
# =============================================================================
set -euo pipefail

ADT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/jit.sh
. "$ADT_DIR/lib/jit.sh"

usage() {
  echo "Usage:" >&2
  echo "  ./sendscreenshot.sh <remote-dir> [-p <profile>]" >&2
  exit 1
}

REMOTE_DIR="${1:-}"
[ -n "$REMOTE_DIR" ] || usage
case "$REMOTE_DIR" in -*) usage ;; esac
shift

PROFILE=""
while [ $# -gt 0 ]; do
  case "$1" in
    -p|--profile)
      [ $# -ge 2 ] || { adt_err "$1 requires a value"; usage; }
      PROFILE="$2"; shift 2 ;;
    *) adt_err "unknown option: $1"; usage ;;
  esac
done

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
IMG="$WORK/screenshot-$(date +%Y%m%d-%H%M%S).png"

# --- Detect + extract the clipboard image into $IMG (per platform) -----------
case "$(uname -s)" in
  Darwin)
    command -v osascript >/dev/null 2>&1 || { adt_err "osascript not found (macOS expected)."; exit 1; }
    INFO="$(osascript -e 'clipboard info' 2>/dev/null || true)"
    case "$INFO" in
      *PNGf*|*TIFF*|*"class PICT"*) ;;
      *) adt_err "clipboard does not hold an image (got: ${INFO:-empty}). Copy a screenshot first."; exit 1 ;;
    esac
    if command -v pngpaste >/dev/null 2>&1; then
      pngpaste "$IMG" || { adt_err "pngpaste failed to read the clipboard image."; exit 1; }
    else
      # Zero-install path: write the clipboard PNG via AppleScript.
      osascript \
        -e 'set thePng to (the clipboard as «class PNGf»)' \
        -e "set fp to open for access (POSIX file \"$IMG\") with write permission" \
        -e 'set eof fp to 0' \
        -e 'write thePng to fp' \
        -e 'close access fp' >/dev/null 2>&1 \
        || { adt_err "could not extract PNG from the clipboard."; exit 1; }
    fi
    ;;
  Linux)
    if [ -n "${WAYLAND_DISPLAY:-}" ] && command -v wl-paste >/dev/null 2>&1; then
      wl-paste --list-types 2>/dev/null | grep -qi '^image/' \
        || { adt_err "clipboard does not hold an image. Copy a screenshot first."; exit 1; }
      wl-paste --type image/png > "$IMG" 2>/dev/null \
        || { adt_err "wl-paste failed to read the clipboard image."; exit 1; }
    elif command -v xclip >/dev/null 2>&1; then
      xclip -selection clipboard -t TARGETS -o 2>/dev/null | grep -qi '^image/' \
        || { adt_err "clipboard does not hold an image. Copy a screenshot first."; exit 1; }
      xclip -selection clipboard -t image/png -o > "$IMG" 2>/dev/null \
        || { adt_err "xclip failed to read the clipboard image."; exit 1; }
    else
      adt_err "need 'wl-paste' (Wayland) or 'xclip' (X11) to read the clipboard image."
      exit 1
    fi
    ;;
  *)
    adt_err "unsupported OS: $(uname -s). Use sendscreenshot.ps1 on Windows."
    exit 1
    ;;
esac

[ -s "$IMG" ] || { adt_err "extracted image is empty; nothing to send."; exit 1; }

# --- Transport: reuse sync.sh push (same JIT/profile/rsync logic) -------------
adt_log "Sending $(basename "$IMG") -> ${REMOTE_DIR%/}/ on the VM"
SYNC_ARGS=(push "$IMG" "$REMOTE_DIR")
[ -n "$PROFILE" ] && SYNC_ARGS+=(-p "$PROFILE")
"$ADT_DIR/sync.sh" "${SYNC_ARGS[@]}"

REMOTE_FILE="${REMOTE_DIR%/}/$(basename "$IMG")"
adt_log "Uploaded. On the VM, reference it in the Copilot CLI with:  @$REMOTE_FILE"
