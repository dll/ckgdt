param(
    [switch]$Restore
)

# Patch sqlite3.dll in sqlite3_flutter_libs package
# The prebuilt sqlite3.dll from sqlite3_flutter_libs v0.5.42 (1.5MB) crashes on first native call
# with 0xC0000005 (null ptr at +0x8 in ntdll). Replace with the good one from sqflite_common_ffi.
# Must be re-run after `flutter pub get` (which may re-download the package).

$prebuiltDir = Join-Path $env:PUB_CACHE "hosted\pub.flutter-io.cn\sqlite3_flutter_libs-0.5.42\windows\prebuilt_sqlite3"
$goodDll = Join-Path $PSScriptRoot "patches\sqlite3.dll"

if ($Restore) {
    if (Test-Path "$prebuiltDir\sqlite3.dll.bak") {
        Copy-Item "$prebuiltDir\sqlite3.dll.bak" "$prebuiltDir\sqlite3.dll" -Force
        Write-Host "Restored original sqlite3.dll"
    }
    return
}

if (!(Test-Path $prebuiltDir)) {
    Write-Host "ERROR: sqlite3_flutter_libs not found at $prebuiltDir"
    exit 1
}

if (!(Test-Path $goodDll)) {
    Write-Host "ERROR: Good sqlite3.dll not found at $goodDll"
    Write-Host "Backup from sqflite_common_ffi package:"
    $sqfliteDlls = Get-ChildItem "$env:PUB_CACHE\hosted\pub.flutter-io.cn\sqflite_common_ffi-*\lib\src\windows\sqlite3.dll"
    foreach ($d in $sqfliteDlls) {
        Write-Host "  $($d.FullName) ($($d.Length) bytes)"
    }
    exit 1
}

# Backup original
if (!(Test-Path "$prebuiltDir\sqlite3.dll.bak")) {
    Copy-Item "$prebuiltDir\sqlite3.dll" "$prebuiltDir\sqlite3.dll.bak" -Force
}

# Patch
Copy-Item $goodDll "$prebuiltDir\sqlite3.dll" -Force
Write-Host "Patched sqlite3.dll: $(Get-Item "$prebuiltDir\sqlite3.dll" | Select-Object Length, LastWriteTime)"
Write-Host "Backup saved as sqlite3.dll.bak"
