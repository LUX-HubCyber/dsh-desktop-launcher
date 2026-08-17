# DeepSeek Harness 桌面端 - 构建脚本（PowerShell 版）
# 用法：在项目目录执行  .\build.ps1
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  DeepSeek Harness 桌面端 - 一键构建脚本" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

if (-not (Get-Command pnpm -ErrorAction SilentlyContinue)) {
    Write-Host "[错误] 未找到 pnpm，请先安装 Node.js (>=22) 与 pnpm。" -ForegroundColor Red
    exit 1
}

# 国内网络加速镜像（如不需要可删除）
$env:ELECTRON_MIRROR = "https://npmmirror.com/mirrors/electron/"
$env:ELECTRON_BUILDER_BINARIES_MIRROR = "https://npmmirror.com/mirrors/electron-builder-binaries/"
# electron-builder 缓存重定向到工作区（post-build-icon.ps1 从该目录查找 rcedit）
$env:ELECTRON_BUILDER_CACHE = Join-Path $PSScriptRoot '.cache\electron-builder'

Write-Host "[1/2] 检查并安装依赖（首次运行会下载 Electron，较慢）..." -ForegroundColor Yellow
if (-not (Test-Path node_modules)) {
    pnpm install
    if ($LASTEXITCODE -ne 0) { throw "依赖安装失败" }
} else {
    Write-Host "      已存在 node_modules，跳过安装。" -ForegroundColor DarkGray
}

Write-Host "[2/2] 构建 + 自动嵌入鲸鱼图标 + 重新打包 ..." -ForegroundColor Yellow
pnpm run build:win
if ($LASTEXITCODE -ne 0) { throw "构建失败" }

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "  构建完成！输出目录：$PSScriptRoot\release" -ForegroundColor Green
Write-Host "    - DeepSeek-Harness-1.0.0-portable.exe  （便携版，双击即用）" -ForegroundColor Green
Write-Host "    - DeepSeek-Harness-Setup-1.0.0.exe    （安装版）" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
