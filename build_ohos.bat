@echo off
REM HarmonyOS HAP 构建脚本 — 用 PowerShell 脚本做 API 兼容补丁
REM
REM 流程：
REM 1. ohos_patch.ps1 — 备份 lib/ + 全局降级 API（withValues/CardThemeData/...）
REM 2. cp pubspec_overrides_ohos.yaml → pubspec_overrides.yaml（依赖降版）
REM 3. flutter pub get + build hap
REM 4. ohos_restore.ps1 — 还原 lib/（无论构建成败都执行）
REM 5. 删 pubspec_overrides.yaml
REM
REM **重要**：本脚本独占 — 跑时不要并行 build 其它平台
REM **如果 build 中断**：手动跑 `powershell ./ohos_restore.ps1` 还原 lib/
REM
REM 工具链路径可用环境变量覆盖（换机器/换开发者无需改脚本）：
REM   FLUTTER_OHOS_HOME  默认 D:\development\flutter_ohos
REM   FLUTTER_STD_HOME   默认 D:\development\flutter_windows_3.35.1-stable
REM   DEVECO_HOME        默认 D:\Program Files\Huawei\DevEco Studio
REM   OHOS_SDK_HOME      默认 E:\Huawei\OpenHarmony\Sdk

setlocal enabledelayedexpansion

if not defined DEVECO_HOME set "DEVECO_HOME=D:\Program Files\Huawei\DevEco Studio"
if not defined OHOS_SDK_HOME set "OHOS_SDK_HOME=E:\Huawei\OpenHarmony\Sdk"
if not defined FLUTTER_OHOS_HOME set "FLUTTER_OHOS_HOME=D:\development\flutter_ohos"
if not defined FLUTTER_STD_HOME set "FLUTTER_STD_HOME=D:\development\flutter_windows_3.35.1-stable"

set "OHPM_HOME=%DEVECO_HOME%\tools\ohpm"
set "HVIGOR_HOME=%DEVECO_HOME%\tools\hvigor"
set "OHOS_BASE_SDK_HOME=%OHOS_SDK_HOME%"
set "PATH=%OHPM_HOME%\bin;%HVIGOR_HOME%\bin;%PATH%"

set "FLUTTER_OHOS=%FLUTTER_OHOS_HOME%\flutter\bin\flutter.bat"
set "FLUTTER_STD=%FLUTTER_STD_HOME%\flutter\bin\flutter.bat"

REM 工具链存在性预检 — 早失败比构建到一半失败好诊断
if not exist "%FLUTTER_OHOS%" (
  echo === ERROR: flutter_ohos 工具链未找到: "%FLUTTER_OHOS%"
  echo ===        设置环境变量 FLUTTER_OHOS_HOME 指向 flutter_ohos 根目录
  exit /b 1
)
if not exist "%OHPM_HOME%\bin" (
  echo === ERROR: ohpm 未找到: "%OHPM_HOME%\bin"
  echo ===        安装 DevEco Studio 或设置环境变量 DEVECO_HOME
  exit /b 1
)

powershell -ExecutionPolicy Bypass -File ohos_patch.ps1
if errorlevel 1 (
  echo === ERROR: ohos_patch.ps1 失败 — 尝试还原 lib/
  goto restore_and_exit
)

copy /Y pubspec_overrides_ohos.yaml pubspec_overrides.yaml >nul

call "%FLUTTER_OHOS%" pub get
call "%FLUTTER_OHOS%" build hap --release
set BUILD_RESULT=%ERRORLEVEL%

del pubspec_overrides.yaml >nul 2>&1

REM 关键：build_ohos 期间 pubspec.lock 被降版（含 record_windows 1.0.6 的
REM 已知 Flutter 3.35.1 native crash bug）。
REM **必须用主 Flutter 工具链**（Dart 3.7+）来 pub upgrade — ohos flutter
REM 内置 Dart 仅 3.4，无法解析 record 6.2.1 / record_windows 1.0.7。
REM
REM 如果这一步漏掉或出错，下次 flutter build windows 会用残留的 1.0.6 lock，
REM 用户语音录音/导航时进程被 native 层秒杀（从日志看不到崩溃栈）。
if exist "%FLUTTER_STD%" (
  call "%FLUTTER_STD%" pub upgrade record record_windows
  if errorlevel 1 (
    echo === !!! pub upgrade record/record_windows FAILED — 桌面语音可能崩溃，请手动跑 !!! ===
  )
) else (
  echo === WARN: 标准 Flutter 工具链未找到: "%FLUTTER_STD%"
  echo ===       跳过 record/record_windows 回升 — 下次 build windows 前请手动:
  echo ===       flutter pub upgrade record record_windows
)

:restore_and_exit
powershell -ExecutionPolicy Bypass -File ohos_restore.ps1
if "%BUILD_RESULT%"=="0" (
  echo === HarmonyOS HAP build SUCCESS ===
) else (
  echo === HarmonyOS HAP build FAILED ===
)
endlocal & exit /b %BUILD_RESULT%
