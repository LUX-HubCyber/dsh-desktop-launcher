# post-build-icon.ps1
# 构建后处理（由 build.bat 在打包完成后调用）：
#   1) 用 rcedit 把鲸鱼图标 + 版本信息嵌入 win-unpacked\DeepSeek Harness.exe；
#   2) 用 --prepackaged 重新打包 portable 版与安装版，让它们内部也带正确图标。
# 用法：powershell -NoProfile -ExecutionPolicy Bypass -File scripts\post-build-icon.ps1
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot

# ---- 1. 定位 rcedit（先查项目内缓存，再查系统默认缓存目录）----
$searchDirs = @(
  (Join-Path $root '.cache\electron-builder'),
  (Join-Path $env:LOCALAPPDATA 'electron-builder\Cache')
)
$rcedit = $null
foreach ($dir in $searchDirs) {
  $rcedit = Get-ChildItem $dir -Recurse -Filter 'rcedit-x64.exe' -ErrorAction SilentlyContinue |
    Select-Object -First 1 -ExpandProperty FullName
  if ($rcedit) { break }
}
if (-not $rcedit) {
  throw '未找到 rcedit-x64.exe（请先完整构建一次以生成 electron-builder 缓存，或设置 ELECTRON_BUILDER_CACHE 指向缓存目录）'
}

$exe = Join-Path $root 'release\win-unpacked\DeepSeek Harness.exe'
$ico = Join-Path $root 'build\icon.ico'
if (-not (Test-Path $exe)) {
  throw '未找到 release\win-unpacked\DeepSeek Harness.exe，请先执行 build.bat 完成打包'
}

# ---- 2. 读取版本与产品名 ----
$pkg = Get-Content (Join-Path $root 'package.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$version = [string]$pkg.version
$productName = [string]$pkg.build.productName
$description = [string]$pkg.description

# ---- 3. rcedit 嵌入图标 + 版本信息（带重试，避免杀软/Defender 瞬时锁文件）----
Write-Host '[post-build] 嵌入鲸鱼图标到 win-unpacked exe ...'
$ok = $false
for ($attempt = 1; $attempt -le 8; $attempt++) {
  & $rcedit $exe `
    --set-icon $ico `
    --set-version-string ProductName $productName `
    --set-version-string FileDescription $description `
    --set-version-string LegalCopyright 'Copyright (c) 2026 DeepSeek Harness Desktop' `
    --set-file-version $version `
    --set-product-version ($version + '.0') `
    --set-version-string InternalName $productName `
    --set-version-string CompanyName 'DeepSeek Harness Desktop'
  if ($LASTEXITCODE -eq 0) { $ok = $true; break }
  Write-Host ("[post-build] rcedit 第 {0} 次尝试失败（可能被杀软/Defender 锁定），2 秒后重试 ..." -f $attempt)
  Start-Sleep -Seconds 2
}
if (-not $ok) {
  throw 'rcedit 嵌入图标失败：exe 可能正被运行中的 DeepSeek Harness 占用，或被杀毒软件锁定。请先关闭应用后重试。'
}

# ---- 4. 重新打包 portable 与安装版 ----
Write-Host '[post-build] 重新打包 portable 与安装版 ...'
Push-Location $root
node node_modules\electron-builder\out\cli\cli.js --prepackaged 'release/win-unpacked' --win portable nsis
$code = $LASTEXITCODE
Pop-Location
if ($code -ne 0) { throw '重新打包失败' }

Write-Host '[post-build] 完成：win-unpacked 已嵌入图标，portable/安装版已重新打包。'
