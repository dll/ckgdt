@echo off
set "OHPM_HOME=D:\Program Files\Huawei\DevEco Studio	ools\ohpm"
set "HVIGOR_HOME=D:\Program Files\Huawei\DevEco Studio	ools\hvigor"
set "OHOS_BASE_SDK_HOME=E:\Huawei\OpenHarmony\Sdk"
set "OHOS_SDK_HOME=E:\Huawei\OpenHarmony\Sdk"
set "PATH=%OHPM_HOME%in;%HVIGOR_HOME%in;%PATH%"
set "FLUTTER_OHOS=D:\developmentlutter_ohoslutterinlutter.bat"
copy /Y pubspec.yaml pubspec_standard.yaml >/dev/null 2>&1
copy /Y pubspec_ohos.yaml pubspec.yaml >/dev/null 2>&1
call "%FLUTTER_OHOS%" pub get
call "%FLUTTER_OHOS%" build hap --release
copy /Y pubspec_standard.yaml pubspec.yaml >/dev/null 2>&1
del pubspec_standard.yaml >/dev/null 2>&1
