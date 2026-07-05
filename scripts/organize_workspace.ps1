param(
  [string]$Date = (Get-Date -Format 'yyyy-MM-dd')
)

$ErrorActionPreference = 'Stop'
$root = Resolve-Path (Join-Path $PSScriptRoot '..')
$logDir = Join-Path $root "logs\build\$Date"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

$patterns = @(
  'build_*_log*.txt',
  'build_log*.txt',
  'build_apk_log*.txt',
  'build_*.log',
  'flutter_*.log',
  'windows_build.log'
)

$moved = @()
$skipped = @()
foreach ($pattern in $patterns) {
  Get-ChildItem -LiteralPath $root -File -Filter $pattern -ErrorAction SilentlyContinue |
    ForEach-Object {
      try {
        $tracked = (& git -C $root ls-files -- $_.Name) 2>$null
        if ($tracked) {
          $skipped += "$($_.Name): tracked by Git"
          return
        }
        Move-Item -LiteralPath $_.FullName -Destination (Join-Path $logDir $_.Name) -Force
        $moved += $_.Name
      } catch {
        $skipped += "$($_.Name): $($_.Exception.Message)"
      }
    }
}

Write-Host "Workspace log cleanup"
Write-Host "Target: $logDir"
Write-Host "Moved: $($moved.Count)"
if ($moved.Count -gt 0) {
  $moved | ForEach-Object { Write-Host "  + $_" }
}
if ($skipped.Count -gt 0) {
  Write-Host "Skipped: $($skipped.Count)"
  $skipped | ForEach-Object { Write-Host "  ! $_" }
}
