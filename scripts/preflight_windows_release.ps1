param(
  [string]$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
  [switch]$Json
)

$ErrorActionPreference = 'Stop'

function Get-BinaryOutputName {
  param([string]$Root)
  $cmakePath = Join-Path $Root 'windows\CMakeLists.txt'
  if (-not (Test-Path -LiteralPath $cmakePath)) {
    throw "windows/CMakeLists.txt not found under $Root"
  }
  $content = Get-Content -LiteralPath $cmakePath -Raw
  $match = [regex]::Match($content, 'BINARY_OUTPUT_NAME\s+"([^"]+)"')
  if (-not $match.Success) {
    throw 'BINARY_OUTPUT_NAME not found in windows/CMakeLists.txt'
  }
  return $match.Groups[1].Value
}

$binaryName = Get-BinaryOutputName -Root $ProjectRoot
$releaseDir = [System.IO.Path]::GetFullPath(
  (Join-Path $ProjectRoot 'build\windows\x64\runner\Release')
)
$exePath = [System.IO.Path]::GetFullPath(
  (Join-Path $releaseDir "$binaryName.exe")
)

$locked = @(Get-Process | ForEach-Object {
  try {
    $path = $_.Path
    if ([string]::IsNullOrWhiteSpace($path)) { return }
    $full = [System.IO.Path]::GetFullPath($path)
    if (
      $full.Equals($exePath, [System.StringComparison]::OrdinalIgnoreCase) -or
      $full.StartsWith($releaseDir, [System.StringComparison]::OrdinalIgnoreCase)
    ) {
      [pscustomobject]@{
        Id = $_.Id
        ProcessName = $_.ProcessName
        Path = $full
      }
    }
  } catch {
  }
})

if ($Json) {
  [pscustomobject]@{
    ok = ($locked.Count -eq 0)
    releaseDir = $releaseDir
    exePath = $exePath
    lockedProcesses = $locked
  } | ConvertTo-Json -Depth 4
}

if ($locked.Count -gt 0) {
  if (-not $Json) {
    Write-Host 'Windows release preflight failed: running process is using the release output directory.' -ForegroundColor Red
    $locked | Format-Table Id, ProcessName, Path -AutoSize
    Write-Host ''
    Write-Host 'Close the process above, then run:' -ForegroundColor Yellow
    Write-Host '  flutter build windows --release'
  }
  exit 2
}

if (-not $Json) {
  Write-Host "Windows release preflight passed: $releaseDir" -ForegroundColor Green
}
exit 0
