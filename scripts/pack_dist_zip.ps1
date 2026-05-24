# UTF-8 safe zip packer (replaces PowerShell 5.1's Compress-Archive,
# which writes ZIP entry names in OEM/GBK encoding -- breaks Linux/macOS unzip).
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File pack_dist_zip.ps1 -SourceDir <dir> -ZipPath <out.zip>
param(
  [Parameter(Mandatory=$true)][string]$SourceDir,
  [Parameter(Mandatory=$true)][string]$ZipPath
)

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

if (Test-Path $ZipPath) { Remove-Item $ZipPath -Force }

$src = (Resolve-Path $SourceDir).Path
$utf8 = [System.Text.Encoding]::UTF8

# CreateFromDirectory(sourceDir, destZip, level, includeBaseDir=false, entryNameEncoding=UTF8)
[System.IO.Compression.ZipFile]::CreateFromDirectory(
  $src,
  $ZipPath,
  [System.IO.Compression.CompressionLevel]::Optimal,
  $false,
  $utf8
)

$mb = [math]::Round((Get-Item $ZipPath).Length / 1MB, 1)
Write-Host "OK: $ZipPath ($mb MB)"
