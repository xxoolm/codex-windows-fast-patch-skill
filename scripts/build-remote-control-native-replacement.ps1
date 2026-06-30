[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$WorkRoot,

  [string]$CodexRepoUrl = 'https://github.com/openai/codex.git',
  [string]$SourceRoot,
  [string]$CacheRoot,
  [string]$TempRoot,
  [string]$TargetRoot,
  [string]$RustToolchain = '1.95.0-x86_64-pc-windows-msvc',
  [string]$BuildTarget = 'x86_64-pc-windows-msvc',
  [string]$BuildProfile = 'dev-small',
  [switch]$SkipClone,
  [switch]$SkipPatch,
  [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'
$ScriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$SkillRoot = Split-Path -Parent $ScriptRoot
$PatchPath = Join-Path $SkillRoot 'references\remote-control-native-replacement.patch'

function Write-Log {
  param([string]$Message)
  Write-Host ("[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $Message)
}

function Fail {
  param([string]$Message)
  throw $Message
}

function Resolve-FullPath {
  param([string]$Path)
  return [System.IO.Path]::GetFullPath($Path)
}

function Get-RequiredCommand {
  param([string]$Name)
  $cmd = Get-Command $Name -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $cmd) {
    Fail "required command not found: $Name"
  }
  return $cmd.Source
}

function Invoke-Checked {
  param(
    [Parameter(Mandatory = $true)][string]$FilePath,
    [Parameter(Mandatory = $true)][string[]]$Arguments,
    [Parameter(Mandatory = $true)][string]$ErrorMessage,
    [string]$WorkingDirectory
  )
  $prefix = if ($WorkingDirectory) { "[$WorkingDirectory] " } else { '' }
  Write-Log "$prefix$FilePath $($Arguments -join ' ')"
  if ($WorkingDirectory) {
    Push-Location -LiteralPath $WorkingDirectory
    try {
      & $FilePath @Arguments 2>&1 | ForEach-Object { $_ }
    } finally {
      Pop-Location
    }
  } else {
    & $FilePath @Arguments 2>&1 | ForEach-Object { $_ }
  }
  if ($LASTEXITCODE -ne 0) {
    Fail "$ErrorMessage (exit code $LASTEXITCODE)"
  }
}

function Test-PathUnderRoot {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Root,
    [Parameter(Mandatory = $true)][string]$Label
  )
  $fullPath = Resolve-FullPath $Path
  $fullRoot = (Resolve-FullPath $Root).TrimEnd('\')
  $comparison = [StringComparison]::OrdinalIgnoreCase
  if ($fullPath.Equals($fullRoot, $comparison) -or $fullPath.StartsWith($fullRoot + '\', $comparison)) {
    return
  }
  Fail "$Label must stay under WorkRoot. $Label=$fullPath WorkRoot=$fullRoot"
}

function Find-Bytes {
  param(
    [Parameter(Mandatory = $true)][byte[]]$Haystack,
    [Parameter(Mandatory = $true)][byte[]]$Needle
  )
  if ($Needle.Length -eq 0 -or $Haystack.Length -lt $Needle.Length) {
    return $false
  }
  $limit = $Haystack.Length - $Needle.Length
  for ($i = 0; $i -le $limit; $i++) {
    if ($Haystack[$i] -ne $Needle[0]) {
      continue
    }
    $matched = $true
    for ($j = 1; $j -lt $Needle.Length; $j++) {
      if ($Haystack[$i + $j] -ne $Needle[$j]) {
        $matched = $false
        break
      }
    }
    if ($matched) {
      return $true
    }
  }
  return $false
}

function Test-BinaryMarkers {
  param(
    [Parameter(Mandatory = $true)][string]$FilePath,
    [Parameter(Mandatory = $true)][string[]]$Markers
  )
  if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) {
    Fail "replacement codex.exe not found: $FilePath"
  }
  $bytes = [System.IO.File]::ReadAllBytes($FilePath)
  $missing = New-Object System.Collections.Generic.List[string]
  foreach ($marker in $Markers) {
    $needle = [System.Text.Encoding]::UTF8.GetBytes($marker)
    if (-not (Find-Bytes -Haystack $bytes -Needle $needle)) {
      $missing.Add($marker)
    }
  }
  if ($missing.Count -gt 0) {
    Fail "replacement codex.exe is missing native remote-control markers: $($missing -join ', ')"
  }
  Write-Log "replacement codex.exe marker check passed: $($Markers.Count)"
}

$WorkRoot = Resolve-FullPath $WorkRoot
if ([string]::IsNullOrWhiteSpace($SourceRoot)) {
  $SourceRoot = Join-Path $WorkRoot 'codex'
}
if ([string]::IsNullOrWhiteSpace($CacheRoot)) {
  $CacheRoot = Join-Path $WorkRoot 'cache'
}
if ([string]::IsNullOrWhiteSpace($TempRoot)) {
  $TempRoot = Join-Path $WorkRoot 'tmp'
}
if ([string]::IsNullOrWhiteSpace($TargetRoot)) {
  $TargetRoot = Join-Path $WorkRoot 'target-msvc'
}

$SourceRoot = Resolve-FullPath $SourceRoot
$CacheRoot = Resolve-FullPath $CacheRoot
$TempRoot = Resolve-FullPath $TempRoot
$TargetRoot = Resolve-FullPath $TargetRoot

foreach ($item in @(
  @{ Path = $SourceRoot; Label = 'SourceRoot' },
  @{ Path = $CacheRoot; Label = 'CacheRoot' },
  @{ Path = $TempRoot; Label = 'TempRoot' },
  @{ Path = $TargetRoot; Label = 'TargetRoot' }
)) {
  Test-PathUnderRoot -Path $item.Path -Root $WorkRoot -Label $item.Label
}

if (-not (Test-Path -LiteralPath $PatchPath -PathType Leaf)) {
  Fail "native patch reference not found: $PatchPath"
}

New-Item -ItemType Directory -Force -Path $WorkRoot, $CacheRoot, $TempRoot, $TargetRoot | Out-Null

$git = Get-RequiredCommand 'git'
$cargo = Get-RequiredCommand 'cargo'

if (-not $SkipClone) {
  if (-not (Test-Path -LiteralPath $SourceRoot -PathType Container)) {
    $parent = Split-Path -Parent $SourceRoot
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    Invoke-Checked -FilePath $git -Arguments @(
      'clone',
      '--filter=blob:none',
      '--depth',
      '1',
      $CodexRepoUrl,
      $SourceRoot
    ) -ErrorMessage 'failed to clone Codex source'
  } else {
    Write-Log "using existing source tree: $SourceRoot"
  }
} elseif (-not (Test-Path -LiteralPath $SourceRoot -PathType Container)) {
  Fail "SkipClone was set but SourceRoot does not exist: $SourceRoot"
}

$gitDir = Join-Path $SourceRoot '.git'
if (-not (Test-Path -LiteralPath $gitDir -PathType Container)) {
  Fail "SourceRoot is not a git checkout: $SourceRoot"
}

if (-not $SkipPatch) {
  & $git -C $SourceRoot apply --reverse --check $PatchPath 2>$null
  if ($LASTEXITCODE -eq 0) {
    Write-Log "native patch already applied"
  } else {
    Invoke-Checked -FilePath $git -Arguments @('-C', $SourceRoot, 'apply', '--check', $PatchPath) -ErrorMessage 'native patch does not apply cleanly'
    Invoke-Checked -FilePath $git -Arguments @('-C', $SourceRoot, 'apply', $PatchPath) -ErrorMessage 'failed to apply native patch'
  }
}

$env:CARGO_HOME = Join-Path $CacheRoot 'cargo'
$env:RUSTUP_HOME = Join-Path $CacheRoot 'rustup'
$env:TEMP = $TempRoot
$env:TMP = $TempRoot
$env:CARGO_TARGET_DIR = $TargetRoot
$env:CARGO_BUILD_JOBS = '1'

Write-Log "CARGO_HOME=$env:CARGO_HOME"
Write-Log "RUSTUP_HOME=$env:RUSTUP_HOME"
Write-Log "TEMP=$env:TEMP"
Write-Log "CARGO_TARGET_DIR=$env:CARGO_TARGET_DIR"

if (-not $SkipBuild) {
  Invoke-Checked -FilePath $cargo -Arguments @(
    "+$RustToolchain",
    'build',
    '--profile',
    $BuildProfile,
    '-p',
    'codex-cli',
    '--target',
    $BuildTarget
  ) -ErrorMessage 'failed to build patched native Codex app-server binary' -WorkingDirectory $SourceRoot
}

$builtExe = Join-Path $TargetRoot "$BuildTarget\$BuildProfile\codex.exe"
$markers = @(
  'remote_control_app_server_isolated_oauth_used',
  'remote_control_native_remote_json_first',
  'remote_control_websocket_proxy_attempt',
  'remote_control_websocket_proxy_connected',
  'remote-control-oauth.json',
  'remote.json',
  'codex.remote_control.enroll'
)
Test-BinaryMarkers -FilePath $builtExe -Markers $markers

Write-Log "replacement native binary ready: $builtExe"
[pscustomobject]@{
  ReplacementResourceCodexExe = $builtExe
  WorkRoot = $WorkRoot
  SourceRoot = $SourceRoot
  CacheRoot = $CacheRoot
  TargetRoot = $TargetRoot
  TempRoot = $TempRoot
} | ConvertTo-Json
