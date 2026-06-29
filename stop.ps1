# =============================================================================
# azure-dev-terminal -- stop.ps1  (Windows; also works via PowerShell on mac/Linux)
# -----------------------------------------------------------------------------
# Deallocate the dev VM on demand: compute cost stops, the OS disk and your data
# are preserved. Restart any time with connect.ps1 (which starts the VM, requests
# JIT, and opens a session). This is the cheap, reversible "pause" -- distinct
# from teardown.ps1, which DELETES the resource group.
#
# Especially relevant for the dedicated/heavy profile, which is too costly to
# leave running 24/7; deallocate it between sessions rather than waiting for the
# daily auto-shutdown backstop.
#
# Deallocate is immediate (no prompt) and idempotent (a no-op if already stopped).
#
# Usage:  ./stop.ps1 [-ConfigFile <path>]    # defaults to vm.lean.conf
#   e.g.  ./stop.ps1                          # RG/VM identical across profiles
#         ./stop.ps1 -ConfigFile vm.heavy.conf
# =============================================================================
[CmdletBinding()]
param(
  [Parameter(Position = 0)]
  [string]$ConfigFile = 'vm.lean.conf'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$AdtDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $AdtDir 'lib/jit.ps1')

$env:ADT_CONFIG = $ConfigFile

Assert-AdtAz
$ctx = Get-AdtConfig -Dir $AdtDir
Stop-AdtVm -Ctx $ctx
Write-AdtLog "VM '$($ctx.Vm)' deallocated. Restart with: ./connect.ps1"
