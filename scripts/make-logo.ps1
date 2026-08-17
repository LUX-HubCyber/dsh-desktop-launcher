# 生成两款 DeepSeek 鲸鱼 Logo（512x512 PNG）：
#   1) build\whale-blue.png  白底 + 蓝色鲸鱼 + 右下角蓝底白字 DSH 斜角标
#   2) build\whale-black.png 白底 + 黑色鲸鱼 + 右下角黑底白字 DSH 斜角标
# 用法：powershell -NoProfile -ExecutionPolicy Bypass -File scripts\make-logo.ps1
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$root = Split-Path -Parent $PSScriptRoot
$svgPath = Join-Path $root 'build\whale.svg'

# ---- 解析鲸鱼 SVG path（仅含 M/C/Z 命令，50x50 viewBox）----
$svg = [System.IO.File]::ReadAllText($svgPath)
$d = [regex]::Match($svg, 'd="([^"]+)"').Groups[1].Value
$tokens = @([regex]::Matches($d, '[MCZ]|[-+]?\d*\.?\d+') | ForEach-Object { $_.Value })

$path = New-Object System.Drawing.Drawing2D.GraphicsPath
$curX = 0.0; $curY = 0.0; $startX = 0.0; $startY = 0.0
for ($i = 0; $i -lt $tokens.Count; $i++) {
  switch ($tokens[$i]) {
    'M' {
      $curX = [double]$tokens[++$i]; $curY = [double]$tokens[++$i]
      $startX = $curX; $startY = $curY
      $path.StartFigure()
    }
    'C' {
      $c1x = [double]$tokens[++$i]; $c1y = [double]$tokens[++$i]
      $c2x = [double]$tokens[++$i]; $c2y = [double]$tokens[++$i]
      $x = [double]$tokens[++$i]; $y = [double]$tokens[++$i]
      $path.AddBezier($curX, $curY, $c1x, $c1y, $c2x, $c2y, $x, $y)
      $curX = $x; $curY = $y
    }
    'Z' {
      $path.CloseFigure()
      $curX = $startX; $curY = $startY
    }
  }
}

# ---- 将 50x50 鲸鱼缩放到 512 画布居中 ----
$s = 7.4
$tx = 256 - $s * 25
$ty = 236 - $s * 25
$matrix = New-Object System.Drawing.Drawing2D.Matrix($s, 0, 0, $s, $tx, $ty)
$path.Transform($matrix)

# ---- 右下角斜角标（平行四边形，黑底）----
function New-BadgePath {
  # 角标：左上(220,390) 右上(512,360) 右下(512,512) 左下(220,512)
  # - 左延展只到 x=220（不再横跨大半个图标）
  # - 顶边斜角坡度放缓并下移，与 DSH 文字留空更小
  # - 上边缘不压到鲸鱼（鲸鱼最低处约 y=370@x=244 / y=349@x=340）
  $bp = New-Object System.Drawing.Drawing2D.GraphicsPath
  $pts = New-Object System.Drawing.PointF[] 4
  $pts[0] = New-Object System.Drawing.PointF(220, 390)
  $pts[1] = New-Object System.Drawing.PointF(512, 360)
  $pts[2] = New-Object System.Drawing.PointF(512, 512)
  $pts[3] = New-Object System.Drawing.PointF(220, 512)
  $bp.AddPolygon($pts)
  return $bp
}

function New-RoundedRectPath([float]$x, [float]$y, [float]$w, [float]$h, [float]$radius) {
  $p = New-Object System.Drawing.Drawing2D.GraphicsPath
  $p.AddArc($x, $y, $radius, $radius, 180, 90)
  $p.AddArc($x + $w - $radius, $y, $radius, $radius, 270, 90)
  $p.AddArc($x + $w - $radius, $y + $h - $radius, $radius, $radius, 0, 90)
  $p.AddArc($x, $y + $h - $radius, $radius, $radius, 90, 90)
  $p.CloseFigure()
  return $p
}

function New-Logo([string]$name, [int]$r, [int]$g2, [int]$b, [int]$br, [int]$bg, [int]$bb) {
  $bmp = New-Object System.Drawing.Bitmap(512, 512)
  $gr = [System.Drawing.Graphics]::FromImage($bmp)
  $gr.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $gr.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAlias

  # 透明背景 + 白色圆角方块
  $gr.Clear([System.Drawing.Color]::Transparent)
  $rounded = New-RoundedRectPath 24 24 464 464 110
  $gr.FillPath([System.Drawing.Brushes]::White, $rounded)

  # 鲸鱼、角标、文字都裁剪在圆角方块内（角标随圆角收边）
  $gr.SetClip($rounded)
  $whaleColor = [System.Drawing.Color]::FromArgb(255, $r, $g2, $b)
  $whaleBrush = New-Object System.Drawing.SolidBrush($whaleColor)
  $gr.FillPath($whaleBrush, $path)

  $badge = New-BadgePath
  $badgeBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, $br, $bg, $bb))
  $gr.FillPath($badgeBrush, $badge)

  # 字符适配裁剪后的角标大小，在角标内居中
  # "DSH"@96 Segoe UI Black 实测宽约 236px（比 Bold 粗 ~27%，小尺寸图标更清晰）
  $font = New-Object System.Drawing.Font('Segoe UI Black', 96, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
  $sf = New-Object System.Drawing.StringFormat
  $sf.Alignment = [System.Drawing.StringAlignment]::Center
  $sf.LineAlignment = [System.Drawing.StringAlignment]::Center
  $sf.FormatFlags = [System.Drawing.StringFormatFlags]::NoWrap
  $gr.DrawString('DSH', $font, [System.Drawing.Brushes]::White, (New-Object System.Drawing.RectangleF(230, 399, 250, 72)), $sf)
  $gr.ResetClip()

  $out = Join-Path $root ("build\" + $name + '.png')
  $bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)

  $gr.Dispose(); $bmp.Dispose(); $whaleBrush.Dispose(); $badgeBrush.Dispose(); $badge.Dispose(); $font.Dispose(); $sf.Dispose(); $rounded.Dispose()
  Write-Host ("wrote " + $out + " (" + (Get-Item $out).Length + " bytes)")
}

New-Logo 'whale-blue' 77 107 254 77 107 254
New-Logo 'whale-black' 0 0 0 0 0 0

$path.Dispose(); $matrix.Dispose()
