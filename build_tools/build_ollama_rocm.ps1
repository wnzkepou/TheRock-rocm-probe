[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
  [string]$OllamaSourcePath = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'ollama-rocm-build\source'),
  [string]$BuildDirectory = '',
  [string]$TheRockInstallPath = (Join-Path $PSScriptRoot '..\install'),
  [string]$OllamaRef = 'main',
  [ValidateRange(1, 128)]
  [int]$Parallel = 2,
  [switch]$UpdateSource
)

$ErrorActionPreference = 'Stop'
$OllamaRepository = 'https://github.com/ollama/ollama.git'
$RepoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$OllamaSourcePath = [IO.Path]::GetFullPath($OllamaSourcePath)
$TheRockInstallPath = [IO.Path]::GetFullPath($TheRockInstallPath)
$TheRockBinPath = Join-Path $TheRockInstallPath 'bin'
$TheRockLlvmBinPath = Join-Path $TheRockInstallPath 'lib\llvm\bin'
$HipCompiler = Join-Path $TheRockLlvmBinPath 'amdclang++.exe'

if ([string]::IsNullOrWhiteSpace($BuildDirectory)) {
  $BuildDirectory = Join-Path (Split-Path -Parent $OllamaSourcePath) 'build-rocm'
}
$BuildDirectory = [IO.Path]::GetFullPath($BuildDirectory)

foreach ($tool in @('git', 'cmake', 'ninja', 'go')) {
  if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
    throw "Required build tool '$tool' was not found in PATH."
  }
}

$cmakeVersionText = (& cmake --version | Select-Object -First 1)
if ($cmakeVersionText -notmatch 'cmake version (\d+)\.(\d+)') {
  throw "Could not determine CMake version from: $cmakeVersionText"
}
if ([version]("$($Matches[1]).$($Matches[2])") -lt [version]'3.24') {
  throw "CMake 3.24 or newer is required; found $cmakeVersionText."
}

if (-not (Test-Path -LiteralPath $TheRockBinPath -PathType Container)) {
  throw "TheRock install bin directory was not found: $TheRockBinPath"
}
foreach ($file in @('hipcc.exe', 'amdhip64_7.dll', 'hsa-runtime64.dll')) {
  if (-not (Test-Path -LiteralPath (Join-Path $TheRockBinPath $file) -PathType Leaf)) {
    throw "TheRock runtime component is missing: $(Join-Path $TheRockBinPath $file)"
  }
}
if (-not (Test-Path -LiteralPath $HipCompiler -PathType Leaf)) {
  throw "TheRock AMD HIP compiler was not found: $HipCompiler"
}

$sourceExists = Test-Path -LiteralPath $OllamaSourcePath
if (-not $sourceExists) {
  if ($PSCmdlet.ShouldProcess($OllamaSourcePath, "Clone $OllamaRepository at '$OllamaRef' with submodules")) {
    New-Item -ItemType Directory -Path (Split-Path -Parent $OllamaSourcePath) -Force | Out-Null
    & git clone --recurse-submodules --branch $OllamaRef -- $OllamaRepository $OllamaSourcePath
    if ($LASTEXITCODE -ne 0) {
      throw "Git clone failed with exit code $LASTEXITCODE."
    }
  } elseif ($WhatIfPreference) {
    Write-Output 'Dry run complete: source clone and build were not started.'
    return
  }
}

if (-not (Test-Path -LiteralPath (Join-Path $OllamaSourcePath '.git'))) {
  throw "Ollama source path exists but is not a Git checkout: $OllamaSourcePath"
}

$origin = (& git -C $OllamaSourcePath remote get-url origin)
if ($LASTEXITCODE -ne 0 -or $origin.TrimEnd('/') -notin @($OllamaRepository, 'https://github.com/ollama/ollama')) {
  throw "The source checkout origin must be $OllamaRepository; found '$origin'."
}

$sourceChanges = & git -C $OllamaSourcePath status --porcelain --untracked-files=all
if ($LASTEXITCODE -ne 0) {
  throw 'Could not inspect the Ollama checkout status.'
}
if ($sourceChanges) {
  throw "The Ollama checkout has local changes. Commit/stash them or choose a clean path: $OllamaSourcePath"
}

if ($UpdateSource) {
  $branchRef = "refs/heads/$OllamaRef"
  & git -C $OllamaSourcePath show-ref --verify --quiet $branchRef
  if ($LASTEXITCODE -ne 0) {
    throw "-UpdateSource requires OllamaRef to be a local branch name; '$OllamaRef' is not one."
  }
  if ($PSCmdlet.ShouldProcess($OllamaSourcePath, "Fast-forward Ollama branch '$OllamaRef'")) {
    & git -C $OllamaSourcePath fetch --prune origin $OllamaRef
    if ($LASTEXITCODE -ne 0) {
      throw "Git fetch failed with exit code $LASTEXITCODE."
    }
    & git -C $OllamaSourcePath merge --ff-only "origin/$OllamaRef"
    if ($LASTEXITCODE -ne 0) {
      throw "Could not fast-forward the Ollama checkout to origin/$OllamaRef."
    }
  }
}

if (-not $WhatIfPreference) {
  & git -C $OllamaSourcePath submodule update --init --recursive
  if ($LASTEXITCODE -ne 0) {
    throw "Ollama submodule initialization failed with exit code $LASTEXITCODE."
  }
}

foreach ($requiredFile in @('CMakeLists.txt', 'go.mod', 'llama\server\CMakeLists.txt')) {
  if (-not (Test-Path -LiteralPath (Join-Path $OllamaSourcePath $requiredFile) -PathType Leaf)) {
    throw "Expected Ollama source file is missing: $(Join-Path $OllamaSourcePath $requiredFile)"
  }
}

$vsWhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$vsDevCmd = $null
if (Test-Path -LiteralPath $vsWhere) {
  $vsInstall = & $vsWhere -latest -products '*' `
    -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
    -property installationPath
  if ($LASTEXITCODE -eq 0 -and $vsInstall) {
    $candidate = Join-Path $vsInstall.Trim() 'Common7\Tools\VsDevCmd.bat'
    if (Test-Path -LiteralPath $candidate) {
      $vsDevCmd = $candidate
    }
  }
}

if (-not $vsDevCmd) {
  $vsCandidates = @(
    'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat'
    'C:\Program Files\Microsoft Visual Studio\2022\Professional\Common7\Tools\VsDevCmd.bat'
    'C:\Program Files\Microsoft Visual Studio\2022\Enterprise\Common7\Tools\VsDevCmd.bat'
    'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\Common7\Tools\VsDevCmd.bat'
  )
  $vsDevCmd = $vsCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
}
if (-not $vsDevCmd) {
  throw 'Visual Studio 2022 C++ tools were not found. Install the Native Desktop workload.'
}

$cmakeBuildTool = (Get-Command cmake).Source
$ninjaBuildTool = (Get-Command ninja).Source

$developerEnvironment = @(
  "call `"$vsDevCmd`" -arch=amd64 -host_arch=amd64 >nul"
  "set `"PATH=$TheRockLlvmBinPath;$TheRockBinPath;$([IO.Path]::GetDirectoryName($ninjaBuildTool));%PATH%`""
  "set `"HIPCXX=$HipCompiler`""
  "set `"CMAKE_PREFIX_PATH=$TheRockInstallPath`""
  "set `"ROCM_PATH=$TheRockInstallPath`""
  "set `"HIP_PATH=$TheRockInstallPath`""
)
$developerEnvironmentCommand = $developerEnvironment -join ' && '

if ($PSCmdlet.ShouldProcess($OllamaSourcePath, 'Configure Ollama with TheRock ROCm 7.1 for gfx1030')) {
  $configureCommand = @(
    "`"$cmakeBuildTool`" -S `"$OllamaSourcePath`" -B `"$BuildDirectory`" -G Ninja"
    "`"-DCMAKE_MAKE_PROGRAM=$ninjaBuildTool`""
    '-DCMAKE_BUILD_TYPE=Release'
    '-DOLLAMA_LLAMA_BACKENDS=rocm_v7_1'
    '-DAMDGPU_TARGETS=gfx1030'
    "`"-DCMAKE_PREFIX_PATH=$TheRockInstallPath`""
    "-DOLLAMA_BUILD_PARALLEL=$Parallel"
  ) -join ' '
  & $env:ComSpec /d /s /c "$developerEnvironmentCommand && $configureCommand"
  if ($LASTEXITCODE -ne 0) {
    throw "Ollama CMake configure failed with exit code $LASTEXITCODE."
  }
} elseif ($WhatIfPreference) {
  Write-Output "Dry run: would configure $OllamaSourcePath into $BuildDirectory."
  return
}

if ($PSCmdlet.ShouldProcess($BuildDirectory, "Build Ollama and its rocm_v7_1 backend with $Parallel jobs")) {
  $buildCommand = "`"$cmakeBuildTool`" --build `"$BuildDirectory`" --parallel $Parallel"
  & $env:ComSpec /d /s /c "$developerEnvironmentCommand && $buildCommand"
  if ($LASTEXITCODE -ne 0) {
    throw "Ollama build failed with exit code $LASTEXITCODE."
  }
} elseif ($WhatIfPreference) {
  Write-Output "Dry run: would build Ollama in $BuildDirectory."
  return
}

$backendPath = Join-Path $BuildDirectory 'lib\ollama\rocm_v7_1'
$backendDll = Join-Path $backendPath 'ggml-hip.dll'
if (-not (Test-Path -LiteralPath $backendDll -PathType Leaf)) {
  throw "The Ollama ROCm backend did not produce the expected DLL: $backendDll"
}

if ($PSCmdlet.ShouldProcess($backendPath, 'Stage TheRock runtime DLL dependencies next to the Ollama ROCm backend')) {
  New-Item -ItemType Directory -Path $backendPath -Force | Out-Null
  foreach ($file in @(
      'amdhip64_7.dll'
      'amd_comgr.dll'
      'hsa-runtime64.dll'
      'rocm_kpack.dll'
      'hiprtc0718.dll'
      'hiprtc-builtins0718.dll'
    )) {
    $source = Join-Path $TheRockBinPath $file
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
      throw "Required TheRock runtime DLL is missing: $source"
    }
    Copy-Item -LiteralPath $source -Destination (Join-Path $backendPath $file) -Force
  }
}

$ollamaExe = Join-Path $OllamaSourcePath 'ollama.exe'
if (-not (Test-Path -LiteralPath $ollamaExe -PathType Leaf)) {
  throw "The Ollama Go executable was not produced: $ollamaExe"
}

Write-Output "Ollama source: $OllamaSourcePath"
Write-Output "Ollama commit: $(& git -C $OllamaSourcePath rev-parse --short HEAD)"
Write-Output "Ollama executable: $ollamaExe"
Write-Output "ROCm backend: $backendDll"
Write-Output "Staged runtime: $backendPath"
Write-Output 'Backend code target: gfx1030. Runtime device selection remains automatic; no GPU index or bus ID is set.'
