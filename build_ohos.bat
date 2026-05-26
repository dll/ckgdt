@echo off
REM HarmonyOS HAP 构建脚本 — 用 PowerShell 脚本做 API 兼容补丁
REM
REM 流程：
REM 1. ohos_patch.ps1 — 备份 lib/ + 全局降级 API（withValues/CardThemeData/...）
REM 2. cp pubspec_overrides_ohos.yaml → pubspec_overrides.yaml（依赖降版）
REM 3. flutter pub get + build hap
REM 4. ohos_restore.ps1 — 还原 lib/
REM 5. 删 pubspec_overrides.yaml
REM
REM **重要**：本脚本独占 — 跑时不要并行 build 其它平台
REM **如果 build 中断**：手动跑 `powershell ./ohos_restore.ps1` 还原 lib/

set "OHPM_HOME=D:\Program Files\Huawei\DevEco Studio\tools\ohpm"
set "HVIGOR_HOME=D:\Program Files\Huawei\DevEco Studio\tools\hvigor"
set "OHOS_BASE_SDK_HOME=E:\Huawei\OpenHarmony\Sdk"
set "OHOS_SDK_HOME=E:\Huawei\OpenHarmony\Sdk"
set "PATH=%OHPM_HOME%\bin;%HVIGOR_HOME%\bin;%PATH%"

powershell -ExecutionPolicy Bypass -File ohos_patch.ps1
if errorlevel 1 goto restore_and_exit

copy /Y pubspec_overrides_ohos.yaml pubspec_overrides.yaml >nul

call D:\development\flutter_ohos\flutter\bin\flutter.bat pub get
call D:\development\flutter_ohos\flutter\bin\flutter.bat build hap --release
set BUILD_RESULT=%ERRORLEVEL%

del pubspec_overrides.yaml >nul 2>&1

REM 关键：build_ohos 期间 pubspec.lock 被降版（含 record_windows 1.0.6 的
REM 已知 Flutter 3.35.1 native crash bug）。
REM **必须用主 Flutter 工具链**（Dart 3.7+）来 pub upgrade — ohos flutter
REM 内置 Dart 仅 3.4，无法解析 record 6.2.1 / record_windows 1.0.7。
REM
REM 如果这一步漏掉或出错，下次 flutter build windows 会用残留的 1.0.6 lock，
REM 用户语音录音/导航时进程被 native 层秒杀（从日志看不到崩溃栈）。
call D:\development\flutter_windows_3.35.1-stable\flutter\bin\flutter.bat pub upgrade record record_windows
if errorlevel 1 (
  echo === !!! pub upgrade record/record_windows FAILED — 桌面语音可能崩溃，请手动跑 !!! ===
)

:restore_and_exit
powershell -ExecutionPolicy Bypass -File ohos_restore.ps1
if "%BUILD_RESULT%"=="0" (
  echo === HarmonyOS HAP build SUCCESS ===
) else (
  echo === HarmonyOS HAP build FAILED ===
)
exit /b %BUILD_RESULT%
