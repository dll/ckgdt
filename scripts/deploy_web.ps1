# deploy_web.ps1 — Build Flutter Web + patch renderer + push gh-pages
param(
  [string]$Version = "v1.16.0",
  [string]$BaseHref = "/mad-kgdt/"
)

$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $PSScriptRoot
$BuildDir = "$RootDir\build\web"
$DeployDir = "$RootDir\build\_gh-pages-deploy"

Write-Host "=== Build Web ==="
# Note: Use MSYS_NO_PATHCONV=1 in Git Bash; in PowerShell the path doesn't get mangled
flutter build web --release --base-href "$BaseHref"

Write-Host "=== Patch: force HTML renderer ==="
$Bootstrap = "$BuildDir\flutter_bootstrap.js"
(Get-Content $Bootstrap -Raw) -replace '"renderer":"canvaskit"', '"renderer":"html"' | Set-Content $Bootstrap

Write-Host "=== Prepare gh-pages deploy ==="
if (Test-Path $DeployDir) { Remove-Item -Recurse -Force $DeployDir }
New-Item -ItemType Directory -Force -Path $DeployDir | Out-Null
Copy-Item -Recurse -Force "$BuildDir\*" $DeployDir

git -C $DeployDir init -q -b gh-pages
git -C $DeployDir config core.longpaths true
git -C $DeployDir add -A
git -C $DeployDir -c user.email="ldl@github" -c user.name="ldl" `
  commit -q -m "deploy: web $Version base=$BaseHref renderer=html"

git -C $DeployDir remote add origin git@github.com:dll/mad-kgdt.git
git -C $DeployDir push -u --force origin gh-pages

Write-Host "=== Clean up ==="
Remove-Item -Recurse -Force $DeployDir

Write-Host "=== Deploy OK ==="
