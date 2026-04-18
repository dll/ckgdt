@echo off
set "OHPM_HOME=D:\Program Files\Huawei\DevEco Studio\tools\ohpm"
set "HVIGOR_HOME=D:\Program Files\Huawei\DevEco Studio\tools\hvigor"
set "OHOS_BASE_SDK_HOME=E:\Huawei\OpenHarmony\Sdk"
set "OHOS_SDK_HOME=E:\Huawei\OpenHarmony\Sdk"
set "PATH=%OHPM_HOME%\bin;%HVIGOR_HOME%\bin;%PATH%"
echo Testing ohpm...
call ohpm --version
echo Testing flutter...
call "D:\development\flutter_ohos\flutter\bin\flutter.bat" build hap --release
