@echo off
chcp 65001 >nul
echo ========================================
echo    课程达成度计算系统
echo ========================================
echo.
echo 正在启动系统...
echo.

python course_achievement_gui.py

if errorlevel 1 (
    echo.
    echo ========================================
    echo    启动失败！
    echo ========================================
    echo.
    echo 可能的原因：
    echo 1. Python未安装或未添加到PATH
    echo 2. 缺少必要的依赖库
    echo.
    echo 解决方法：
    echo 1. 安装Python 3.7或更高版本
    echo 2. 运行: pip install pandas numpy matplotlib seaborn python-docx
    echo.
    pause
)