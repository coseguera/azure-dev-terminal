# =============================================================================
# azure-dev-terminal -- connect.ps1  (Windows; also works via PowerShell on mac/Linux)
# -----------------------------------------------------------------------------
# Connect to the dev VM over Microsoft Entra ID SSH with Just-in-Time access:
#   1. Start the VM if it is deallocated.
#   2. Request JIT access for port 22 from this machine's source (auto-closes).
#   3. Open an Entra ID SSH session (ephemeral certificate). No VNC, no tunnel.
#
# Usage:  ./connect.ps1 [-NetworkProfile <name>] [-Dev [-Path <dir>]]
#   ./connect.ps1                                  # shell; JIT source = detected IP (/32)
#   ./connect.ps1 -NetworkProfile nat              # shell; CIDRs from connect.nat.local
#   ./connect.ps1 -Dev                             # nvim at $HOME with Copilot in the float
#   ./connect.ps1 -Dev -Path '~/dev/proj'          # nvim at that dir with Copilot in the float
#   ./connect.ps1 -NetworkProfile nat -Dev -Path '~/work'   # combine profile with dev mode
#
# For networks behind a multi-range NAT pool, create a profile once:
#   'JIT_SRC=203.0.113.0/24,198.51.100.0/24' | Set-Content connect.nat.local
#
# Dev mode (-Dev) opens nvim on the VM and auto-starts the Copilot CLI in its floating
# terminal (via ADT_DEV=1, handled by the staged nvim config). Requires a pseudo-tty,
# which `az ssh vm -- -t` allocates.
#
# VM identity (LOC/RG/VM) is read from the VM config; override with $env:ADT_CONFIG.
# =============================================================================
[CmdletBinding()]
param(
  [Alias('p')]
  [string]$NetworkProfile = '',

  [switch]$Dev,

  [string]$Path = '',

  [string]$JitDuration = 'PT3H'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$AdtDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $AdtDir 'lib/jit.ps1')

Assert-AdtAz
$ctx = Get-AdtConfig -Dir $AdtDir
Invoke-AdtEnsureAccess -Ctx $ctx -NetworkProfile $NetworkProfile -Duration $JitDuration -Dir $AdtDir

if ($Dev) {
  # Build the remote command: open nvim (in $Path if given) with Copilot auto-started.
  if ([string]::IsNullOrEmpty($Path) -or $Path -eq '~') {
    $remoteCmd = 'ADT_DEV=1 nvim'
  } else {
    # Single-quote the path for the remote shell, escaping any embedded single quotes.
    $q = $Path -replace "'", "'\''"
    $remoteCmd = "cd '$q' && ADT_DEV=1 nvim ."
  }
  Write-AdtLog "Opening Entra ID SSH session to $($ctx.Vm) (dev mode: nvim + Copilot) ..."
  az ssh vm -g $ctx.Rg -n $ctx.Vm '--' '-t' $remoteCmd
  return
}

Write-AdtLog "Opening Entra ID SSH session to $($ctx.Vm) ..."
az ssh vm -g $ctx.Rg -n $ctx.Vm
