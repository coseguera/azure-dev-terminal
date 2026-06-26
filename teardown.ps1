# =============================================================================
# azure-dev-terminal -- teardown.ps1  (Windows; also works via PowerShell on mac/Linux)
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
# Usage:  ./teardown.ps1 [-ConfigFile <path>]    # defaults to vm.lean.conf
#   e.g.  ./teardown.ps1
#         ./teardown.ps1 -ConfigFile vm.heavy.conf
# =============================================================================
[CmdletBinding()]
param(
  [Parameter(Position = 0)]
  [string]$ConfigFile = 'vm.lean.conf'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$AdtDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $AdtDir
$Rendered = 'cloud-init/azure/custom-data'   # gitignored; produced by provision.sh

function Write-AdtLog { param([string]$Message) Write-Host ">> $Message" }

# ===================== Configuration =====================
$cfgPath = if (Test-Path $ConfigFile) { $ConfigFile } else { Join-Path $AdtDir $ConfigFile }
if (-not (Test-Path $cfgPath)) {
  $avail = (Get-ChildItem -Path $AdtDir -Filter 'vm.*.conf' -ErrorAction SilentlyContinue | ForEach-Object { $_.Name }) -join ' '
  Write-Error "config file not found: $ConfigFile`n       e.g.:  ./teardown.ps1 -ConfigFile vm.lean.conf`n       (available: $avail)"
  exit 1
}
Write-AdtLog "Using configuration: $ConfigFile"

# Parse the shell-style VM config (KEY="value" lines) for LOC/RG/VM.
$cfg = @{}
foreach ($line in Get-Content $cfgPath) {
  if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*"?([^"#]*?)"?\s*(#.*)?$') {
    $cfg[$matches[1]] = $matches[2]
  }
}
foreach ($k in 'LOC', 'RG', 'VM') {
  if (-not $cfg.ContainsKey($k) -or [string]::IsNullOrWhiteSpace($cfg[$k])) {
    Write-Error "set $k in $ConfigFile"
    exit 1
  }
}
$Loc = $cfg['LOC']; $Rg = $cfg['RG']; $Vm = $cfg['VM']
# =========================================================

if (-not (Get-Command az -ErrorAction SilentlyContinue)) { throw "Azure CLI (az) not found." }
az account show 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) { throw "run 'az login' first." }

az group show -n $Rg 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
  Write-AdtLog "Resource group '$Rg' does not exist; nothing to delete."
  Write-AdtLog "(You may still want to check Defender for Servers below.)"
}

$Sub = az account show --query id -o tsv
# Resolve the signed-in user and VM id BEST-EFFORT: the VM may already be gone, and the
# role assignment delete just becomes a no-op in that case.
$UserOid = az ad signed-in-user show --query id -o tsv 2>$null
$VmId = az vm show -g $Rg -n $Vm --query id -o tsv 2>$null

Write-Host ''
Write-Host '========================================================'
Write-Host ' TEARDOWN -- this will DELETE the following:'
Write-Host "   - Resource group:   $Rg   (in $Loc)"
Write-Host "       includes VM '$Vm', NSG, NIC, public IP, OS disk,"
Write-Host '       AAD SSH extension, auto-shutdown schedule, JIT policy'
Write-Host "   - Role assignment:  'Virtual Machine Administrator Login' on the VM"
Write-Host "   - Local artifact:   $Rendered (if present)"
Write-Host ' Defender for Servers Plan 2 (subscription-wide) is handled separately below.'
Write-Host '========================================================'
Write-Host ''
Write-Host ' This is IRREVERSIBLE. To confirm, type the resource group name exactly.'
$confirm = Read-Host ">> Type '$Rg' to delete, or anything else to abort"
if ($confirm -ne $Rg) {
  Write-AdtLog 'Confirmation did not match. Aborted; nothing was deleted.'
  exit 1
}

# --- Best-effort: remove the VM-scoped role assignment ---
# (Deleting the VM would orphan it anyway, but we clean it up explicitly.)
if (-not [string]::IsNullOrWhiteSpace($UserOid) -and -not [string]::IsNullOrWhiteSpace($VmId)) {
  Write-AdtLog "Removing 'Virtual Machine Administrator Login' role assignment"
  az role assignment delete --assignee-object-id $UserOid --role 'Virtual Machine Administrator Login' --scope $VmId -o none 2>$null
  if ($LASTEXITCODE -ne 0) { Write-Host '   (no matching role assignment, or already removed)' }
} else {
  Write-AdtLog 'Skipping role assignment cleanup (VM or signed-in user not resolved)'
}

# --- Best-effort: delete the JIT network access policy (also covered by RG delete) ---
Write-AdtLog 'Deleting Just-in-Time access policy (if present)'
$jitUrl = "https://management.azure.com/subscriptions/$Sub/resourceGroups/$Rg/providers/Microsoft.Security/locations/$Loc/jitNetworkAccessPolicies/default?api-version=2020-01-01"
az rest --method delete --url $jitUrl -o none 2>$null
if ($LASTEXITCODE -ne 0) { Write-Host '   (no JIT policy, or already removed)' }

# --- Delete the resource group (waits so you see it finish) ---
az group show -n $Rg 2>$null | Out-Null
if ($LASTEXITCODE -eq 0) {
  Write-AdtLog "Deleting resource group $Rg (this takes a few minutes)..."
  az group delete -n $Rg --yes -o none
  Write-Host '   Resource group deleted.'
} else {
  Write-AdtLog "Resource group $Rg already absent; skipping."
}

# --- Defender for Servers Plan 2 (SUBSCRIPTION-WIDE) ---
Write-Host ''
Write-Host 'Microsoft Defender for Servers Plan 2 is enabled per SUBSCRIPTION, not per VM.'
Write-Host 'Disabling it affects EVERY server in this subscription (and may reduce protection'
Write-Host 'and JIT for other VMs). Only disable it if this VM was the reason it was on.'
$answer = Read-Host '>> Disable Defender for Servers Plan 2 subscription-wide now? [y/N]'
if ($answer -match '^[Yy]$') {
  az security pricing create -n VirtualMachines --tier free -o none
  Write-Host '   Defender for Servers set to the free tier.'
} else {
  Write-Host '   Left Defender for Servers unchanged.'
}

# --- Best-effort: remove the local rendered custom-data artifact ---
if (Test-Path $Rendered) {
  Write-AdtLog "Removing local rendered artifact: $Rendered"
  Remove-Item $Rendered -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host '========================================================'
Write-Host ' Teardown complete.'
Write-Host " Re-create anytime with:  ./provision.sh $ConfigFile"
Write-Host '========================================================'
