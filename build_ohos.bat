@echo off
set "OHPM_HOME=D:\Program Files\Huawei\DevEco Studio\tools\ohpm"
set "HVIGOR_HOME=D:\Program Files\Huawei\DevEco Studio\tools\hvigor"
set "OHOS_BASE_SDK_HOME=E:\Huawei\OpenHarmony\Sdk"
set "OHOS_SDK_HOME=E:\Huawei\OpenHarmony\Sdk"
set "PATH=%OHPM_HOME%\bin;%HVIGOR_HOME%\bin;%PATH%"
copy /Y pubspec.yaml pubspec_standard.yaml >nul
copy /Y pubspec_ohos.yaml pubspec.yaml >nul
call D:\development\flutter_ohos\flutter\bin\flutter.bat pub get
call D:\development\flutter_ohos\flutter\bin\flutter.bat build hap --release
copy /Y pubspec_standard.yaml pubspec.yaml >nul
del pubspec_standard.yaml >nul
