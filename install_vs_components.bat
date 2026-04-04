@echo off
echo ============================================
echo   安装 Flutter Windows 桌面开发所需组件
echo ============================================
echo.
echo 正在通过 Visual Studio Installer 安装:
echo   - C++ CMake tools for Windows
echo   - Windows 10/11 SDK
echo.
echo 请等待安装完成...
echo.

"C:\Program Files (x86)\Microsoft Visual Studio\Installer\setup.exe" modify --installPath "D:\Program Files\Microsoft Visual Studio\18\Community" --add Microsoft.VisualStudio.Component.VC.CMake.Project --add Microsoft.VisualStudio.Component.Windows10SDK.19041 --add Microsoft.VisualStudio.Component.Windows10SDK.20348 --add Microsoft.VisualStudio.Component.Windows11SDK.22621 --add Microsoft.VisualStudio.Component.Windows11SDK.26100 --passive --norestart

if %errorlevel% equ 0 (
    echo.
    echo ============================================
    echo   安装成功！请回到终端运行:
    echo   flutter build windows --release
    echo ============================================
) else (
    echo.
    echo ============================================
    echo   安装可能未完成，错误代码: %errorlevel%
    echo   请手动打开 Visual Studio Installer
    echo   选择"修改" -^> 勾选"使用C++的桌面开发"
    echo ============================================
)

pause
