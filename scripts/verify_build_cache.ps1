#!/usr/bin/env pwsh
<#
.SYNOPSIS
    构建前缓存验证 — 检查本地缓存是否齐全，避免每次构建都重新下载。

.DESCRIPTION
    在 flutter build 之前运行，验证以下缓存完整性：
    - PUB_CACHE (Dart 包缓存)
    - Gradle 缓存 (gradle wrapper + android dependencies)
    - Android SDK
    - ANGLE.7z (Windows 视频解码)
    - sqlite3.dll 补丁状态
    - Flutter SDK

    输出 JSON 状态报告，或打印人类可读的结果。

.EXAMPLE
    ./scripts/verify_build_cache.ps1                   # 打印检查结果
    ./scripts/verify_build_cache.ps1 -Json              # 输出 JSON 供脚本调用
    ./scripts/verify_build_cache.ps1 -Fix               # 尝试修复可修复的问题
#>

param(
    [switch]$Json,
    [switch]$Fix
)

$ErrorActionPreference = 'Continue'

function New-Result {
    param($Category, $Status, $Message, $Fixable)
    [pscustomobject]@{
        category = $Category
        status   = $Status   # 'ok' / 'warn' / 'fail' / 'skip'
        message  = $Message
        fixable  = $Fixable
    }
}

[System.Collections.Generic.List[object]]$results = @()

# ── 1. Flutter SDK ────────────────────────────────────────────────────
$flutter = Get-Command 'flutter' -ErrorAction SilentlyContinue
if ($flutter) {
    $flutterDir = Split-Path -Parent (Split-Path -Parent $flutter.Source)
    $flutterVer = & flutter --version 2>&1 | Select-String -Pattern '^Flutter ' | ForEach-Object { $_.ToString().Trim() }
    $results.Add((New-Result -Category 'Flutter SDK' -Status 'ok' -Message "$flutterVer ($flutterDir)" -Fixable $false))
} else {
    $results.Add((New-Result -Category 'Flutter SDK' -Status 'fail' -Message '未找到 flutter 命令，检查 PATH' -Fixable $true))
}

# ── 2. PUB_CACHE (Dart 包) ────────────────────────────────────────────
$pubCache = $env:PUB_CACHE
if (-not $pubCache) {
    $pubCache = "$env:USERPROFILE\AppData\Local\Pub\Cache"
}
if (Test-Path -LiteralPath "$pubCache\hosted") {
    $pkgCount = (Get-ChildItem -LiteralPath "$pubCache\hosted" -Recurse -Directory -Depth 2 2>$null).Count
    $cacheSize = [math]::Round(((Get-ChildItem -LiteralPath $pubCache -Recurse -File 2>$null | Measure-Object -Property Length -Sum).Sum / 1MB), 1)
    $results.Add((New-Result -Category 'PUB_CACHE' -Status 'ok' -Message "$pubCache ($pkgCount+ packages, ${cacheSize}MB)" -Fixable $false))
} else {
    $results.Add((New-Result -Category 'PUB_CACHE' -Status 'fail' -Message "$pubCache 不存在" -Fixable $true))
}

# ── 3. Gradle 缓存 ────────────────────────────────────────────────────
$gradleHome = $env:GRADLE_USER_HOME
if (-not $gradleHome) {
    $gradleHome = "$env:USERPROFILE\.gradle"
}
$gradleWrapper = "$gradleHome\wrapper\dists"
$gradleCaches = "$gradleHome\caches"
$gradleOk = $false
if (Test-Path -LiteralPath $gradleCaches) {
    $gradleModules = Get-ChildItem -LiteralPath "$gradleCaches\modules-2\files-2.1" -Directory 2>$null
    $gradleOk = $true
    $results.Add((New-Result -Category 'Gradle 缓存' -Status 'ok' -Message "$gradleHome ($($gradleModules.Count) modules)" -Fixable $false))
} else {
    $results.Add((New-Result -Category 'Gradle 缓存' -Status 'warn' -Message "$gradleHome — 缓存未找到，首次构建会下载" -Fixable $true))
}

# ── 4. Gradle Wrapper ────────────────────────────────────────────────
if (Test-Path -LiteralPath $gradleWrapper) {
    $wrapperVersions = Get-ChildItem -LiteralPath $gradleWrapper -Directory | ForEach-Object Name
    $okFiles = Get-ChildItem -LiteralPath $gradleWrapper -Recurse -Filter '*.ok' 2>$null
    $results.Add((New-Result -Category 'Gradle Wrapper' -Status 'ok' -Message "$($wrapperVersions -join ', ') ($($okFiles.Count) .ok 标记)" -Fixable $false))
} else {
    $results.Add((New-Result -Category 'Gradle Wrapper' -Status 'warn' -Message "wrapper 缓存不存在，首次构建会下载" -Fixable $true))
}

# ── 5. Android SDK ────────────────────────────────────────────────────
$androidHome = $env:ANDROID_HOME
if (-not $androidHome) { $androidHome = "$env:LOCALAPPDATA\Android\Sdk" }
if (Test-Path -LiteralPath "$androidHome\platforms") {
    $platforms = Get-ChildItem -LiteralPath "$androidHome\platforms" -Directory | ForEach-Object Name
    $buildTools = Get-ChildItem -LiteralPath "$androidHome\build-tools" -Directory | ForEach-Object Name
    $ndkPresent = Test-Path -LiteralPath "$androidHome\ndk"
    $results.Add((New-Result -Category 'Android SDK' -Status 'ok' -Message "$androidHome — platforms=$($platforms -join ','), build-tools=$($buildTools -join ','), ndk=$ndkPresent" -Fixable $false))
} else {
    $results.Add((New-Result -Category 'Android SDK' -Status 'fail' -Message "$androidHome 不存在或未配置" -Fixable $true))
}

# ── 6. ANGLE.7z (Windows 构建) ───────────────────────────────────────
$angleDir = "build\windows\x64"
if (Test-Path -LiteralPath $angleDir) {
    $angleFile = Get-ChildItem -LiteralPath $angleDir -Filter 'ANGLE.7z' 2>$null
    if ($angleFile) {
        $results.Add((New-Result -Category 'ANGLE.7z' -Status 'ok' -Message "$($angleFile.FullName) ($([math]::Round($angleFile.Length/1MB,1)) MB)" -Fixable $false))
    } else {
        $results.Add((New-Result -Category 'ANGLE.7z' -Status 'warn' -Message "未找到 ANGLE.7z — Windows 首次构建会下载" -Fixable $true))
    }
} else {
    $results.Add((New-Result -Category 'ANGLE.7z' -Status 'skip' -Message "未构建过 Windows，跳过" -Fixable $false))
}

# ── 7. sqlite3.dll 补丁状态 ──────────────────────────────────────────
$sqliteCache = "$env:PUB_CACHE\hosted\pub.flutter-io.cn"
$sqliteFiles = Get-ChildItem -LiteralPath "$sqliteCache" -Recurse -Filter 'sqlite3.dll' -Depth 6 2>$null
$needPatch = $false
foreach ($dll in $sqliteFiles) {
    if ($dll.Length -lt 2000000) {
        $needPatch = $true
        break
    }
}
if ($needPatch) {
    $results.Add((New-Result -Category 'sqlite3.dll' -Status 'warn' -Message "需要补丁（小尺寸 dll 检测到），运行 scripts/patch_sqlite3.ps1" -Fixable $true))
} elseif ($sqliteFiles) {
    $results.Add((New-Result -Category 'sqlite3.dll' -Status 'ok' -Message "已补丁（大尺寸 dll）" -Fixable $false))
} else {
    $results.Add((New-Result -Category 'sqlite3.dll' -Status 'skip' -Message "未找到 sqlite3.dll（未 pub get 过）" -Fixable $false))
}

# ── 8. pubspec.lock（依赖已解析） ──────────────────────────────────────
if (Test-Path -LiteralPath 'pubspec.lock') {
    $depCount = (Select-String -LiteralPath 'pubspec.lock' -Pattern '^\s+name: ' | Measure-Object).Count
    $results.Add((New-Result -Category 'pubspec.lock' -Status 'ok' -Message "$depCount 个依赖已锁定" -Fixable $false))
} else {
    $results.Add((New-Result -Category 'pubspec.lock' -Status 'fail' -Message "未找到 pubspec.lock，运行 flutter pub get" -Fixable $true))
}

# ── 汇总 ──────────────────────────────────────────────────────────────
$okCount = ($results | Where-Object { $_.status -eq 'ok' }).Count
$warnCount = ($results | Where-Object { $_.status -eq 'warn' }).Count
$failCount = ($results | Where-Object { $_.status -eq 'fail' }).Count
$totalCount = $results.Count

if ($Json) {
    $results | ConvertTo-Json -Depth 4
    return
}

$iconMap = @{ 'ok' = '✓'; 'warn' = '⚠'; 'fail' = '✗'; 'skip' = '…' }
$colorMap = @{ 'ok' = 'Green'; 'warn' = 'Yellow'; 'fail' = 'Red'; 'skip' = 'Gray' }

Write-Host ""
Write-Host "═══════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  构建缓存状态报告" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════" -ForegroundColor Cyan
foreach ($r in $results) {
    $icon = $iconMap[$r.status]
    $color = $colorMap[$r.status]
    Write-Host "$icon [$($r.category)] $($r.message)" -ForegroundColor $color
}
Write-Host "───────────────────────────────────────────────" -ForegroundColor Gray
$statusColor = if ($failCount -gt 0) { 'Red' } elseif ($warnCount -gt 0) { 'Yellow' } else { 'Green' }
Write-Host " $okCount/$totalCount 通过, $warnCount 警告, $failCount 失败" -ForegroundColor $statusColor

if ($failCount -gt 0) {
    Write-Host ""
    Write-Host "✗ 构建前请修复以上失败项。运行本脚本时加 -Fix 参数自动修复。" -ForegroundColor Red
    exit 1
}
if ($warnCount -gt 0) {
    Write-Host "⚠  $warnCount 个警告（首次构建可忽略）" -ForegroundColor Yellow
}
