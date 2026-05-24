# OHOS 构建后还原 lib/
$ErrorActionPreference = 'Stop'

if (Test-Path 'lib.backup') {
    if (Test-Path 'lib') {
        Remove-Item -Recurse -Force 'lib'
    }
    Rename-Item 'lib.backup' 'lib'
    Write-Host "lib restored from backup"
} else {
    Write-Warning "lib.backup not found, no restore"
}
