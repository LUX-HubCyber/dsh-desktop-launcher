@echo off
setlocal
chcp 936 >nul 2>nul
cd /d "%~dp0.."

echo ============================================================
echo   DeepSeek Harness - 图标一键生成脚本
echo   (重新生成 build\ 下的鲸鱼 Logo 与 .ico 图标)
echo ============================================================
echo.

set PS=powershell -NoProfile -ExecutionPolicy Bypass -File

echo [1/3] 生成鲸鱼 Logo（白底蓝鲸 + 白底黑鲸）...
%PS% scripts\make-logo.ps1
if errorlevel 1 (
    echo [错误] Logo 生成失败，请查看上方日志。
    pause
    exit /b 1
)

echo.
echo [2/3] 生成两款 .ico 图标（whale-blue.ico / whale-black.ico）...
%PS% scripts\make-icon.ps1 -InputPng build\whale-blue.png -OutputIco build\whale-blue.ico
if errorlevel 1 (
    echo [错误] 蓝鲸 .ico 生成失败。
    pause
    exit /b 1
)
%PS% scripts\make-icon.ps1 -InputPng build\whale-black.png -OutputIco build\whale-black.ico
if errorlevel 1 (
    echo [错误] 黑鲸 .ico 生成失败。
    pause
    exit /b 1
)

echo.
echo [3/3] 重新生成当前应用的 icon.png -^> icon.ico ...
%PS% scripts\make-icon.ps1
if errorlevel 1 (
    echo [错误] icon.ico 生成失败。
    pause
    exit /b 1
)

echo.
echo ============================================================
echo   完成！build\ 目录下的图标文件已更新：
echo     - whale-blue.png / whale-blue.ico
echo     - whale-black.png / whale-black.ico
echo     - icon.png / icon.ico （当前应用版）
echo ============================================================
pause
