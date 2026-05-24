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
    $c = $c -replace '\.withValues\(alpha:\s*([^)]+)\)', '.withOpacity($1)'
    # Theme classes 去 Data 后缀
    $c = $c -replace 'CardThemeData\(', 'CardTheme('
    $c = $c -replace 'DialogThemeData\(', 'DialogTheme('
    $c = $c -replace 'TabBarThemeData\(', 'TabBarTheme('
    # PopScope.onPopInvokedWithResult → onPopInvoked
    $c = $c -replace 'onPopInvokedWithResult:', 'onPopInvoked:'
    # DropdownButtonFormField.initialValue → value
    $c = $c -replace 'DropdownButtonFormField<([^>]+)>\(\s*initialValue:', 'DropdownButtonFormField<$1>(value:'
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

Write-Host "OHOS patch done"
