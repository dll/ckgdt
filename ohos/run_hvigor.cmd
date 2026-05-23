@echo off
set "PATH=D:\Program Files\Huawei\DevEco Studio\tools\ohpm\bin;D:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin;%PATH%"
call hvigorw assembleHap -p product=default -p buildMode=release --no-daemon --stacktrace
