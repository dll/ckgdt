# OHOS 构建前的源码补丁脚本
# 用法：powershell -ExecutionPolicy Bypass -File ohos_patch.ps1
#
# 把 lib/ 下使用了 Flutter 3.27+ 新 API 的代码降级到 flutter_ohos
# 当前 SDK (Flutter ~3.16) 兼容版本。
#
# 替换前先备份 lib → lib.backup；构建结束 ohos_restore.ps1 还原。

$ErrorActionPreference = 'Stop'

# 1) 备份 lib/
if (Test-Path 'lib.backup') {
    Remove-Item -Recurse -Force 'lib.backup'
}
Copy-Item -Recurse 'lib' 'lib.backup'

# 2) 全局批量替换
$files = Get-ChildItem -Path 'lib' -Filter '*.dart' -Recurse
$count = 0
foreach ($f in $files) {
    $c = Get-Content $f.FullName -Raw -Encoding UTF8
    $orig = $c
    # Color.withValues({alpha: x}) → Color.withOpacity(x)
    $c = $c -replace '\.withValues\(\s*alpha:\s*([^)]+)\)', '.withOpacity($1)'
    # Theme classes 去 Data 后缀
    $c = $c -replace 'CardThemeData\(', 'CardTheme('
    $c = $c -replace 'DialogThemeData\(', 'DialogTheme('
    $c = $c -replace 'TabBarThemeData\(', 'TabBarTheme('
    # PopScope.onPopInvokedWithResult → onPopInvoked
    $c = $c -replace 'onPopInvokedWithResult:', 'onPopInvoked:'
    # DropdownButtonFormField.initialValue → value
    $c = $c -replace 'DropdownButtonFormField<([^>]+)>\(\s*initialValue:', 'DropdownButtonFormField<$1>(value:'
    # activeThumbColor on SwitchListTile (Flutter 3.27+) → remove
    $c = $c -replace '\s*activeThumbColor:\s*[^,]+,\s*', ' '
    $c = $c -replace '\s*activeThumbColor:\s*[^\n;]+', ''
    # Color.toARGB32() (Flutter 3.27+) → Color.value
    $c = $c -replace '\.toARGB32\(\)', '.value'
    if ($c -ne $orig) {
        Set-Content -Path $f.FullName -Value $c -Encoding UTF8 -NoNewline
        $count++
    }
}
Write-Host "patched $count files"

# 3) main.dart 移除 i18n gen 引用
$mainPath = 'lib/main.dart'
$c = Get-Content $mainPath -Raw -Encoding UTF8
$c = $c -replace "import 'l10n/gen/app_localizations.dart';\r?\n?", ''
$c = $c -replace 'AppL10n\.supportedLocales', 'const [Locale("zh"), Locale("en")]'
$c = $c -replace 'AppL10n\.localizationsDelegates', 'const []'
Set-Content -Path $mainPath -Value $c -Encoding UTF8 -NoNewline

# 4) webview 页桩替换 — OHOS flutter fork (Dart 3.4) 只能用 webview_flutter 3.0.4，
#    teaching_task_authorized_fetch_page.dart 用了 4.x API，编译会失败。
#    用 ohos/stubs/ 下的同名桩（保持公开 API）覆盖；ohos_restore.ps1 还原。
$webviewPage = 'lib/presentation/pages/archive/teaching_task_authorized_fetch_page.dart'
$webviewStub = 'ohos/stubs/teaching_task_authorized_fetch_page.dart'
if (Test-Path $webviewStub) {
    Copy-Item -Path $webviewStub -Destination $webviewPage -Force
    Write-Host "stubbed webview page for OHOS"
} else {
    Write-Warning "webview stub not found: $webviewStub"
}

Write-Host "OHOS patch done"
