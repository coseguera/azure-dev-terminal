# =============================================================================
# azure-dev-terminal -- sendscreenshot.ps1  (Windows; also works via PowerShell on mac/Linux)
# -----------------------------------------------------------------------------
# Upload a screenshot that is ALREADY on your local clipboard to a directory on
# the dev VM, then print the VM path so you can @-mention it in the Copilot CLI.
#
#   ./sendscreenshot.ps1 <remote-dir> [-p <name>]
#
# It proceeds ONLY if the clipboard holds bitmap IMAGE data; copied text or a
# copied FILE reference is refused so nothing is sent by accident. The clipboard
# is left untouched. Transport reuses sync.ps1 (Entra ID SSH cert + rsync + JIT),
# so the same network profiles apply.
# =============================================================================
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true, Position = 0)]
  [string]$RemoteDir,

  [Alias('p')]
  [string]$NetworkProfile = '',

  [string]$JitDuration = 'PT3H'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$AdtDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $AdtDir 'lib/jit.ps1')

$work = Join-Path ([System.IO.Path]::GetTempPath()) ("adt-shot-" + [System.Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null
try {
  $img = Join-Path $work ("screenshot-" + (Get-Date -Format 'yyyyMMdd-HHmmss') + ".png")

  # --- Detect + extract the clipboard image into $img -----------------------
  if ($IsMacOS) {
    $info = (& osascript -e 'clipboard info' 2>$null)
    if ($info -notmatch 'PNGf|TIFF|class PICT') {
      throw "clipboard does not hold an image (got: $info). Copy a screenshot first."
    }
    if (Get-Command pngpaste -ErrorAction SilentlyContinue) {
      & pngpaste $img
    } else {
      $script = @(
        'set thePng to (the clipboard as «class PNGf»)',
        "set fp to open for access (POSIX file `"$img`") with write permission",
        'set eof fp to 0',
        'write thePng to fp',
        'close access fp'
      )
      & osascript ($script | ForEach-Object { '-e'; $_ }) | Out-Null
    }
  } elseif ($IsLinux) {
    if ($env:WAYLAND_DISPLAY -and (Get-Command wl-paste -ErrorAction SilentlyContinue)) {
      if (((& wl-paste --list-types) -join "`n") -notmatch '(?im)^image/') {
        throw "clipboard does not hold an image. Copy a screenshot first."
      }
      & wl-paste --type image/png | Set-Content -LiteralPath $img -AsByteStream
    } elseif (Get-Command xclip -ErrorAction SilentlyContinue) {
      if (((& xclip -selection clipboard -t TARGETS -o) -join "`n") -notmatch '(?im)^image/') {
        throw "clipboard does not hold an image. Copy a screenshot first."
      }
      & xclip -selection clipboard -t image/png -o | Set-Content -LiteralPath $img -AsByteStream
    } else {
      throw "need 'wl-paste' (Wayland) or 'xclip' (X11) to read the clipboard image."
    }
  } else {
    # Windows
    Add-Type -AssemblyName System.Windows.Forms
    if (-not [System.Windows.Forms.Clipboard]::ContainsImage()) {
      throw "clipboard does not hold an image. Copy a screenshot first."
    }
    $bmp = [System.Windows.Forms.Clipboard]::GetImage()
    try { $bmp.Save($img, [System.Drawing.Imaging.ImageFormat]::Png) }
    finally { $bmp.Dispose() }
  }

  if (-not (Test-Path -LiteralPath $img) -or (Get-Item -LiteralPath $img).Length -eq 0) {
    throw "extracted image is empty; nothing to send."
  }

  # --- Transport: reuse sync.ps1 push (same JIT/profile/rsync logic) ---------
  Write-AdtLog ("Sending " + (Split-Path -Leaf $img) + " -> " + ($RemoteDir.TrimEnd('/') + '/') + " on the VM")
  $syncArgs = @('push', $img, $RemoteDir)
  if ($NetworkProfile) { $syncArgs += @('-p', $NetworkProfile) }
  $syncArgs += @('-JitDuration', $JitDuration)
  & (Join-Path $AdtDir 'sync.ps1') @syncArgs

  $remoteFile = $RemoteDir.TrimEnd('/') + '/' + (Split-Path -Leaf $img)
  Write-AdtLog "Uploaded. On the VM, reference it in the Copilot CLI with:  @$remoteFile"
} finally {
  Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
}
