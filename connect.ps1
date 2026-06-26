# =============================================================================
# azure-dev-terminal -- connect.ps1  (Windows; also works via PowerShell on mac/Linux)
# -----------------------------------------------------------------------------
# Connect to the dev VM over Microsoft Entra ID SSH with Just-in-Time access:
#   1. Start the VM if it is deallocated.
#   2. Request JIT access for port 22 from this machine's source (auto-closes).
#   3. Open an Entra ID SSH session (ephemeral certificate). No VNC, no tunnel.
#
# Usage:  ./connect.ps1 [-Profile <name>]
#   ./connect.ps1                 # JIT source = this machine's detected public IP (/32)
#   ./connect.ps1 -NetworkProfile nat   # JIT source = CIDRs from connect.nat.local (gitignored)
#
# For networks behind a multi-range NAT pool, create a profile once:
#   'JIT_SRC=203.0.113.0/24,198.51.100.0/24' | Set-Content connect.nat.local
#
# VM identity (LOC/RG/VM) is read from the VM config; override with $env:ADT_CONFIG.
# =============================================================================
[CmdletBinding()]
param(
  [Parameter(Position = 0)]
  [string]$NetworkProfile = '',

  [string]$JitDuration = 'PT3H'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$AdtDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $AdtDir 'lib/jit.ps1')

Assert-AdtAz
$ctx = Get-AdtConfig -Dir $AdtDir
Invoke-AdtEnsureAccess -Ctx $ctx -NetworkProfile $NetworkProfile -Duration $JitDuration -Dir $AdtDir

Write-AdtLog "Opening Entra ID SSH session to $($ctx.Vm) ..."
az ssh vm -g $ctx.Rg -n $ctx.Vm
