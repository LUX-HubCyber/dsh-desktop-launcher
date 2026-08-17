@echo off
setlocal
cd /d "%~dp0"

echo ============================================================
echo   DeepSeek Harness 桌面端 - 一键构建脚本
echo ============================================================
echo.

where pnpm >nul 2>nul
if errorlevel 1 (
    echo [错误] 未找到 pnpm，请先安装 Node.js ^(^>=22^) 与 pnpm。
    echo 安装 Node.js: https://nodejs.org/
    echo 安装 pnpm:   npm install -g pnpm
    pause
    exit /b 1
)

REM ---- 国内网络加速镜像（如网络较慢可保留；如不需要可注释掉）----
set ELECTRON_MIRROR=https://npmmirror.com/mirrors/electron/
set ELECTRON_BUILDER_BINARIES_MIRROR=https://npmmirror.com/mirrors/electron-builder-binaries/
REM ---- electron-builder cache redirected into workspace (post-build-icon.ps1 looks for rcedit here) ----
set ELECTRON_BUILDER_CACHE=%~dp0.cache\electron-builder
REM --------------------------------------------------------------

echo [1/2] 检查并安装依赖（首次运行会下载 Electron，较慢）...
if not exist node_modules (
    call pnpm install
    if errorlevel 1 (
        echo [错误] 依赖安装失败，请检查网络后重试。
        pause
        exit /b 1
    )
) else (
    echo        已存在 node_modules，跳过安装。
)

echo.
echo [2/2] 构建 + 自动嵌入鲸鱼图标 + 重新打包 ...
call pnpm run build:win
if errorlevel 1 (
    echo [错误] 构建失败，请查看上方日志。
    pause
    exit /b 1
)

echo.
echo ============================================================
echo   构建完成！输出目录：%~dp0release
echo     - DeepSeek-Harness-1.0.0-portable.exe  （便携版，双击即用）
echo     - DeepSeek-Harness-Setup-1.0.0.exe    （安装版）
echo   注：win-unpacked 与安装版内的 DeepSeek Harness.exe 均已嵌入鲸鱼图标。
echo ============================================================
pause
