# =============================================================================
# azure-dev-terminal -- lib/jit.ps1
# -----------------------------------------------------------------------------
# Shared helpers for Entra ID SSH + Just-in-Time (JIT) access. Dot-sourced by both
# connect.ps1 and sync.ps1 so the JIT / CIDR-source logic lives in ONE place.
# PowerShell parity for lib/jit.sh.
#
# Provides:
#   Assert-AdtAz                 - verify az is installed, logged in, ssh ext present
#   Get-AdtConfig                - read the VM config (LOC/RG/VM); returns a context
#   Resolve-AdtSource [profile]  - return @{ Src; Prefixes } (detected /32 or profile)
#   Start-AdtVm $ctx             - start the VM if it is deallocated
#   Request-AdtJit $ctx $src [d] - request JIT access (port 22) for the source(s)
# =============================================================================

Set-StrictMode -Version Latest

function Write-AdtLog { param([string]$Message) Write-Host ">> $Message" }

function Assert-AdtAz {
  if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw "Azure CLI (az) not found."
  }
  az account show 2>$null | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "run 'az login' first." }
  az extension show -n ssh 2>$null | Out-Null
  if ($LASTEXITCODE -ne 0) { az extension add -n ssh -y -o none | Out-Null }
}

# Parse the shell-style VM config (KEY="value" lines) for LOC/RG/VM, then resolve
# SUB and VM_ID from Azure. Override which config to read with $env:ADT_CONFIG.
function Get-AdtConfig {
  param([string]$Dir)
  $cfgName = if ($env:ADT_CONFIG) { $env:ADT_CONFIG } else { 'vm.lean.conf' }
  $cfgPath = if (Test-Path $cfgName) { $cfgName } else { Join-Path $Dir $cfgName }
  if (-not (Test-Path $cfgPath)) { throw "VM config not found: $cfgName (set ADT_CONFIG)" }

  $cfg = @{}
  foreach ($line in Get-Content $cfgPath) {
    if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*"?([^"#]*?)"?\s*(#.*)?$') {
      $cfg[$matches[1]] = $matches[2]
    }
  }
  foreach ($k in 'LOC','RG','VM') {
    if (-not $cfg.ContainsKey($k) -or [string]::IsNullOrWhiteSpace($cfg[$k])) {
      throw "set $k in $cfgName"
    }
  }
  $sub  = az account show --query id -o tsv
  $vmId = az vm show -g $cfg['RG'] -n $cfg['VM'] --query id -o tsv
  if ([string]::IsNullOrWhiteSpace($vmId)) { throw "could not resolve VM id for $($cfg['VM']) in $($cfg['RG'])" }

  return [pscustomobject]@{
    Loc = $cfg['LOC']; Rg = $cfg['RG']; Vm = $cfg['VM']; Sub = $sub; VmId = $vmId
  }
}

# Resolve the JIT source range(s). With no profile: this machine's detected public IP
# (a /32). With a profile name: the CIDR list from connect.<name>.local (gitignored).
function Resolve-AdtSource {
  param([string]$Dir, [string]$NetworkProfile)
  $src = $null
  if ($NetworkProfile) {
    $pf = Join-Path $Dir "connect.$NetworkProfile.local"
    if (-not (Test-Path $pf)) {
      throw "network profile not found: $pf`n       create it with: 'JIT_SRC=<cidr>[,<cidr>...]' > connect.$NetworkProfile.local"
    }
    foreach ($line in Get-Content $pf) {
      if ($line -match '^\s*JIT_SRC\s*=\s*"?([^"#]*?)"?\s*(#.*)?$') { $src = $matches[1] }
    }
    Write-AdtLog "Using network profile: $NetworkProfile"
  }
  if (-not $src) {
    $src = (Invoke-RestMethod -Uri 'https://api.ipify.org')
  }
  $prefixes = @($src -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
  return [pscustomobject]@{ Src = $src; Prefixes = $prefixes }
}

function Start-AdtVm {
  param([pscustomobject]$Ctx)
  Write-AdtLog "Ensuring VM is running..."
  az vm start -g $Ctx.Rg -n $Ctx.Vm -o none 2>$null | Out-Null
}

# Request JIT access for port 22 from the given source(s). $Duration is ISO 8601.
function Request-AdtJit {
  param([pscustomobject]$Ctx, [pscustomobject]$Source, [string]$Duration = 'PT3H')
  Write-AdtLog "Requesting JIT access (port 22) for source(s): $($Source.Src)"
  $body = @{
    virtualMachines = @(
      @{
        id    = $Ctx.VmId
        ports = @(
          @{
            number                       = 22
            duration                     = $Duration
            allowedSourceAddressPrefixes = $Source.Prefixes
          }
        )
      }
    )
    justification = 'interactive dev session'
  } | ConvertTo-Json -Depth 6 -Compress

  $url = "https://management.azure.com/subscriptions/$($Ctx.Sub)/resourceGroups/$($Ctx.Rg)/providers/Microsoft.Security/locations/$($Ctx.Loc)/jitNetworkAccessPolicies/default/initiate?api-version=2020-01-01"
  # Pass the JSON body via a temp file so quoting survives across platforms.
  $tmp = New-TemporaryFile
  try {
    Set-Content -Path $tmp -Value $body -Encoding ascii
    az rest --method post --url $url --body "@$tmp" -o none
  } finally {
    Remove-Item $tmp -ErrorAction SilentlyContinue
  }
  Write-AdtLog "Waiting for the access rule to take effect..."
  Start-Sleep -Seconds 12
}
