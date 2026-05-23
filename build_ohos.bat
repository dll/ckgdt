@echo off
REM HarmonyOS HAP 构建脚本 — 用 pubspec_overrides.yaml 模式
REM
REM 流程：
REM 1. cp pubspec_overrides_ohos.yaml → pubspec_overrides.yaml
REM    （pub get 时 Dart 自动合并依赖覆盖，主 pubspec 不动）
REM 2. flutter pub get + build hap
REM 3. 删 pubspec_overrides.yaml 恢复主 pubspec 不被污染
REM
REM 比 pubspec_ohos.yaml 整文件复制好在：主 pubspec 升级时本脚本无需同步

set "OHPM_HOME=D:\Program Files\Huawei\DevEco Studio\tools\ohpm"
set "HVIGOR_HOME=D:\Program Files\Huawei\DevEco Studio\tools\hvigor"
set "OHOS_BASE_SDK_HOME=E:\Huawei\OpenHarmony\Sdk"
set "OHOS_SDK_HOME=E:\Huawei\OpenHarmony\Sdk"
set "PATH=%OHPM_HOME%\bin;%HVIGOR_HOME%\bin;%PATH%"

copy /Y pubspec_overrides_ohos.yaml pubspec_overrides.yaml >nul
call D:\development\flutter_ohos\flutter\bin\flutter.bat pub get
call D:\development\flutter_ohos\flutter\bin\flutter.bat build hap --release
del pubspec_overrides.yaml >nul
