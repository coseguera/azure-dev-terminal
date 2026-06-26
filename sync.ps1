# =============================================================================
# azure-dev-terminal -- sync.ps1  (Windows; also works via PowerShell on mac/Linux)
# -----------------------------------------------------------------------------
# One-way rsync of a file OR directory between this machine and the dev VM, over
# Microsoft Entra ID SSH. Run it on demand; it does not disturb an open connect session.
#
#   ./sync.ps1 push <local-path> <remote-dir> [-p <name>] [-Delete] [-DryRun]   # local -> VM
#   ./sync.ps1 pull <remote-path> <local-dir> [-p <name>] [-Delete] [-DryRun]   # VM    -> local
#
# Arguments are scp-style: always <source> then <destination>. The SOURCE may be a
# file or a directory; the DESTINATION is the PARENT directory it lands in (created
# if missing). The source basename is preserved, like 'cp' / 'scp'.
#
# Access: if port 22 is already open (a connect session running / JIT live) it syncs
# immediately; otherwise it requests JIT itself (same logic + profiles as connect.ps1).
# Transport is a short-lived Entra SSH cert via 'az ssh config'.
#
# Requires 'rsync' and 'ssh' on PATH. On Windows these come with WSL or Git for Windows.
# =============================================================================
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true, Position = 0)]
  [ValidateSet('push', 'pull')]
  [string]$Direction,

  [Parameter(Mandatory = $true, Position = 1)]
  [string]$Source,

  [Parameter(Mandatory = $true, Position = 2)]
  [string]$Destination,

  [Alias('p')]
  [string]$NetworkProfile = '',

  [switch]$Delete,
  [switch]$DryRun,
  [string]$JitDuration = 'PT3H'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$AdtDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $AdtDir 'lib/jit.ps1')

foreach ($tool in 'rsync', 'ssh') {
  if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
    throw "'$tool' not found on PATH. On Windows, install WSL or Git for Windows."
  }
}

# Map the scp-style source/destination onto local vs remote by direction.
if ($Direction -eq 'push') {
  $LocalPath = $Source; $RemotePath = $Destination
  if (-not (Test-Path -LiteralPath $LocalPath)) { throw "local source does not exist: $LocalPath" }
} else {
  $RemotePath = $Source; $LocalPath = $Destination
}

Assert-AdtAz
$ctx = Get-AdtConfig -Dir $AdtDir
Invoke-AdtEnsureAccess -Ctx $ctx -NetworkProfile $NetworkProfile -Duration $JitDuration -Dir $AdtDir

# --- Build a short-lived Entra SSH config for rsync's transport ---
$work = Join-Path ([System.IO.Path]::GetTempPath()) ("adt-" + [System.Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null
try {
  $cfg = Join-Path $work 'config'
  az ssh config -g $ctx.Rg -n $ctx.Vm --file $cfg --keys-dest-folder $work --overwrite -o none

  $hostAlias = $null
  foreach ($line in Get-Content $cfg) {
    if ($line -match '^\s*Host\s+(.+)$') {
      foreach ($h in ($matches[1] -split '\s+')) { if ($h -and $h -ne '*') { $hostAlias = $h; break } }
      if ($hostAlias) { break }
    }
  }
  if (-not $hostAlias) { throw "could not parse Host from generated ssh config." }

  # accept-new + a throwaway known_hosts avoids any interactive host-key prompt.
  $known = Join-Path $work 'known_hosts'
  $sshCmd = "ssh -F `"$cfg`" -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=`"$known`""

  # No trailing slash on the source: rsync places it (file or dir) by basename UNDER
  # the destination directory, matching cp/scp semantics.
  $rsyncArgs = @('-a', '-v', '--exclude', '.DS_Store')
  if ($Delete) { $rsyncArgs += '--delete' }
  if ($DryRun) { $rsyncArgs += '--dry-run' }
  $rsyncArgs += @('-e', $sshCmd)

  if ($Direction -eq 'push') {
    $srcClean = $LocalPath.TrimEnd('/', '\')
    $dstRemote = $RemotePath.TrimEnd('/') + '/'
    Write-AdtLog "PUSH  $srcClean  ->  ${hostAlias}:$dstRemote"
    & ssh -F $cfg -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=$known $hostAlias "mkdir -p '$dstRemote'"
    & rsync @rsyncArgs $srcClean "${hostAlias}:$dstRemote"
  } else {
    $srcRemote = $RemotePath.TrimEnd('/')
    $dstLocal = $LocalPath.TrimEnd('/', '\') + [System.IO.Path]::DirectorySeparatorChar
    Write-AdtLog "PULL  ${hostAlias}:$srcRemote  ->  $dstLocal"
    New-Item -ItemType Directory -Force -Path $dstLocal | Out-Null
    & rsync @rsyncArgs "${hostAlias}:$srcRemote" $dstLocal
  }
  Write-AdtLog "Done."
} finally {
  Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
}
