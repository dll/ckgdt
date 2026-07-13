@echo off
chcp 65001 >nul
echo ========================================
echo    安装课程达成度计算系统依赖
echo ========================================
echo.

echo 正在检查Python环境...
python --version >nul 2>&1
if errorlevel 1 (
    echo [错误] 未找到Python！
    echo 请先安装Python 3.7或更高版本
    echo 下载地址: https://www.python.org/downloads/
    pause
    exit /b 1
)

echo [成功] Python环境检查通过
echo.

echo 正在安装依赖库...
echo.

echo [1/5] 正在安装 pandas...
pip install pandas
if errorlevel 1 (
    echo [错误] pandas安装失败
    pause
    exit /b 1
)
echo [成功] pandas安装完成
echo.

echo [2/5] 正在安装 numpy...
pip install numpy
if errorlevel 1 (
    echo [错误] numpy安装失败
    pause
    exit /b 1
)
echo [成功] numpy安装完成
echo.

echo [3/5] 正在安装 matplotlib...
pip install matplotlib
if errorlevel 1 (
    echo [错误] matplotlib安装失败
    pause
    exit /b 1
)
echo [成功] matplotlib安装完成
echo.

echo [4/5] 正在安装 seaborn...
pip install seaborn
if errorlevel 1 (
    echo [错误] seaborn安装失败
    pause
    exit /b 1
)
echo [成功] seaborn安装完成
echo.

echo [5/5] 正在安装 python-docx...
pip install python-docx
if errorlevel 1 (
    echo [错误] python-docx安装失败
    pause
    exit /b 1
)
echo [成功] python-docx安装完成
echo.

echo ========================================
echo    所有依赖安装完成！
echo ========================================
echo.
echo 现在可以运行"启动系统.bat"来启动系统
echo.
pause