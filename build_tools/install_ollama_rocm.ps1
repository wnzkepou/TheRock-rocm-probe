[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
  [string]$TheRockInstallPath = (Join-Path $PSScriptRoot '..\install'),
  [string]$OllamaInstallPath = (Join-Path $env:LOCALAPPDATA 'Programs\Ollama'),
  [string]$BackupRoot = (Join-Path $env:LOCALAPPDATA 'Ollama\TheRock-backups')
)

$ErrorActionPreference = 'Stop'
$TheRockBinPath = Join-Path $TheRockInstallPath 'bin'
$OllamaExePath = Join-Path $OllamaInstallPath 'ollama.exe'
$OllamaBackendPath = Join-Path $OllamaInstallPath 'lib\ollama\rocm_v7_1'
$RequiredRuntimeFiles = @(
  'amdhip64_7.dll'
  'hsa-runtime64.dll'
  'hiprtc0718.dll'
  'hiprtc-builtins0718.dll'
)

if (-not (Test-Path -LiteralPath $TheRockBinPath -PathType Container)) {
  throw "TheRock install bin directory was not found: $TheRockBinPath. Build and install TheRock first."
}

foreach ($file in $RequiredRuntimeFiles) {
  $sourcePath = Join-Path $TheRockBinPath $file
  if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
    throw "Required TheRock runtime file is missing: $sourcePath"
  }
}

if (-not (Test-Path -LiteralPath $OllamaExePath -PathType Leaf)) {
  $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
  if (-not $winget) {
    throw 'Ollama is not installed and winget.exe was not found. Install winget, then rerun this script.'
  }

  if ($PSCmdlet.ShouldProcess('Ollama.Ollama', 'Install Ollama with winget')) {
    & $winget.Source install --id Ollama.Ollama --exact --silent `
      --accept-source-agreements --accept-package-agreements --disable-interactivity
    if ($LASTEXITCODE -ne 0) {
      throw "winget failed to install Ollama (exit code $LASTEXITCODE)."
    }
  } elseif ($WhatIfPreference) {
    Write-Output 'Dry run: Ollama would be installed with winget.'
    return
  }
}

if (-not (Test-Path -LiteralPath $OllamaExePath -PathType Leaf)) {
  throw "Ollama executable was not found after installation: $OllamaExePath"
}
if (-not (Test-Path -LiteralPath $OllamaBackendPath -PathType Container)) {
  throw "Ollama's rocm_v7_1 backend was not found: $OllamaBackendPath. Update or reinstall Ollama, then rerun this script."
}

$runningOllama = Get-Process -Name ollama -ErrorAction SilentlyContinue
if ($runningOllama -and -not $WhatIfPreference) {
  throw 'Ollama is running. Exit Ollama completely and rerun this script so its backend DLLs can be safely updated.'
}
if ($runningOllama) {
  Write-Output 'Dry run: Ollama must be fully exited before DLLs can be updated.'
}

$filesToReplace = @()
foreach ($file in $RequiredRuntimeFiles) {
  $sourcePath = Join-Path $TheRockBinPath $file
  $destinationPath = Join-Path $OllamaBackendPath $file
  if (-not (Test-Path -LiteralPath $destinationPath -PathType Leaf)) {
    $filesToReplace += $file
    continue
  }

  $sourceHash = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash
  $destinationHash = (Get-FileHash -LiteralPath $destinationPath -Algorithm SHA256).Hash
  if ($sourceHash -ne $destinationHash) {
    $filesToReplace += $file
  }
}

if ($filesToReplace.Count -gt 0) {
  $backupPath = Join-Path $BackupRoot (
    (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
  )
  if ($PSCmdlet.ShouldProcess($OllamaBackendPath, "Back up existing runtime DLLs and stage TheRock runtime files")) {
    New-Item -ItemType Directory -Path $backupPath -Force | Out-Null
    foreach ($file in $filesToReplace) {
      $destinationPath = Join-Path $OllamaBackendPath $file
      if (Test-Path -LiteralPath $destinationPath -PathType Leaf) {
        Copy-Item -LiteralPath $destinationPath -Destination (Join-Path $backupPath $file)
      }
      Copy-Item -LiteralPath (Join-Path $TheRockBinPath $file) -Destination $destinationPath -Force
    }
    Write-Output "Backed up replaced Ollama runtime files to: $backupPath"
  }
} else {
  Write-Output 'Ollama ROCm runtime DLLs already match the TheRock installation.'
}

$requiredEnvironment = @{
  GPU_ENABLE_PAL = '0'
  OLLAMA_LLM_LIBRARY = 'rocm_v7_1'
  OLLAMA_VULKAN = '0'
}
foreach ($name in $requiredEnvironment.Keys) {
  $value = $requiredEnvironment[$name]
  if ($PSCmdlet.ShouldProcess("User environment variable $name", "Set to $value")) {
    [Environment]::SetEnvironmentVariable($name, $value, 'User')
    [Environment]::SetEnvironmentVariable($name, $value, 'Process')
  }
}

$deviceFilterVariables = @(
  'HIP_VISIBLE_DEVICES'
  'ROCR_VISIBLE_DEVICES'
  'GPU_DEVICE_ORDINAL'
  'GGML_VK_VISIBLE_DEVICES'
)
foreach ($name in $deviceFilterVariables) {
  if ($null -ne [Environment]::GetEnvironmentVariable($name, 'User') -or
      $null -ne [Environment]::GetEnvironmentVariable($name, 'Process')) {
    if ($PSCmdlet.ShouldProcess("User and process environment variable $name", 'Remove device-index filter')) {
      [Environment]::SetEnvironmentVariable($name, $null, 'User')
      [Environment]::SetEnvironmentVariable($name, $null, 'Process')
    }
  }
}

if (-not $WhatIfPreference) {
  foreach ($file in $RequiredRuntimeFiles) {
    $sourceHash = (Get-FileHash -LiteralPath (Join-Path $TheRockBinPath $file) -Algorithm SHA256).Hash
    $destinationHash = (Get-FileHash -LiteralPath (Join-Path $OllamaBackendPath $file) -Algorithm SHA256).Hash
    if ($sourceHash -ne $destinationHash) {
      throw "Runtime DLL verification failed after staging: $file"
    }
  }
  foreach ($name in $requiredEnvironment.Keys) {
    if ([Environment]::GetEnvironmentVariable($name, 'User') -ne $requiredEnvironment[$name]) {
      throw "Persistent environment variable was not set as expected: $name"
    }
  }
  foreach ($name in $deviceFilterVariables) {
    if ($null -ne [Environment]::GetEnvironmentVariable($name, 'User')) {
      throw "Device-index filter remains in the user environment: $name"
    }
  }

  Write-Output 'Ollama is configured to use TheRock ROCm with automatic GPU discovery.'
  Write-Output 'No GPU index or PCI/bus address has been selected.'
  Write-Output 'Fully exit and reopen Ollama for the persistent environment changes to take effect.'
} else {
  Write-Output 'Dry run complete: no files or environment variables were changed.'
}
