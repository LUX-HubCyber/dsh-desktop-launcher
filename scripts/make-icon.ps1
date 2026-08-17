# Generate a multi-size .ico (BMP/DIB entries, exact colors + alpha) from a PNG.
# Usage:
#   make-icon.ps1                          # build\icon.png -> build\icon.ico
#   make-icon.ps1 -InputPng build\whale-black.png -OutputIco build\whale-black.ico
param(
  [string]$InputPng = 'build/icon.png',
  [string]$OutputIco = 'build/icon.ico'
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$root = Split-Path -Parent $PSScriptRoot
$srcPath = Join-Path $root $InputPng
$outPath = Join-Path $root $OutputIco
$sizes = @(16, 24, 32, 48, 64, 128, 256)

function New-IcoDibEntry([System.Drawing.Bitmap]$bitmap) {
  $w = $bitmap.Width
  $h = $bitmap.Height
  $rect = New-Object System.Drawing.Rectangle(0, 0, $w, $h)
  $data = $bitmap.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $stride = [Math]::Abs($data.Stride)
  $raw = New-Object byte[] ($stride * $h)
  [System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $raw, 0, $raw.Length)
  $bitmap.UnlockBits($data)

  # White-fill fully-transparent pixels (alpha=0) so that renderers which ignore
  # the alpha channel show white (not black) at the rounded corners.
  for ($i = 0; $i -lt $raw.Length; $i += 4) {
    if ($raw[$i + 3] -eq 0) {
      $raw[$i] = 255
      $raw[$i + 1] = 255
      $raw[$i + 2] = 255
    }
  }

  $xorSize = $w * $h * 4
  $andStride = [int]([Math]::Ceiling($w / 32.0) * 4)
  $andSize = $andStride * $h
  $dib = New-Object byte[] (40 + $xorSize + $andSize)

  # BITMAPINFOHEADER (40 bytes, little-endian)
  [BitConverter]::GetBytes([int]40).CopyTo($dib, 0)              # biSize
  [BitConverter]::GetBytes([int]$w).CopyTo($dib, 4)             # biWidth
  [BitConverter]::GetBytes([int]($h * 2)).CopyTo($dib, 8)       # biHeight = XOR + AND
  [BitConverter]::GetBytes([UInt16]1).CopyTo($dib, 12)          # biPlanes
  [BitConverter]::GetBytes([UInt16]32).CopyTo($dib, 14)         # biBitCount
  [BitConverter]::GetBytes([int]0).CopyTo($dib, 16)             # biCompression = BI_RGB
  [BitConverter]::GetBytes([int]($xorSize + $andSize)).CopyTo($dib, 20)  # biSizeImage

  # XOR: bottom-up rows (LockBits gives top-down BGRA)
  for ($y = 0; $y -lt $h; $y++) {
    $srcRow = ($h - 1 - $y) * $stride
    $dstRow = 40 + $y * ($w * 4)
    [System.Array]::Copy($raw, $srcRow, $dib, $dstRow, ($w * 4))
  }
  # AND mask stays all-zero (alpha channel controls transparency)
  return $dib
}

$src = [System.Drawing.Bitmap]::FromFile($srcPath)
$entries = @()
foreach ($size in $sizes) {
  $bmp = New-Object System.Drawing.Bitmap($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
  $g.Clear([System.Drawing.Color]::Transparent)
  $g.DrawImage($src, 0, 0, $size, $size)
  $g.Dispose()
  $entry = New-IcoDibEntry $bmp
  $bmp.Dispose()
  $entries += ,$entry
  Write-Host ("built {0} px -> {1} bytes" -f $size, $entry.Length)
}
$src.Dispose()

$count = $sizes.Count
$offset = 6 + 16 * $count
$fs = [System.IO.File]::Create($outPath)
$bw = New-Object System.IO.BinaryWriter($fs)
$bw.Write([UInt16]0)
$bw.Write([UInt16]1)
$bw.Write([UInt16]$count)
for ($i = 0; $i -lt $count; $i++) {
  $size = $sizes[$i]
  if ($size -eq 256) { $dim = 0 } else { $dim = $size }
  $dib = $entries[$i]
  $bw.Write([Byte]$dim)
  $bw.Write([Byte]$dim)
  $bw.Write([Byte]0)
  $bw.Write([Byte]0)
  $bw.Write([UInt16]1)
  $bw.Write([UInt16]32)
  $bw.Write([UInt32]$dib.Length)
  $bw.Write([UInt32]$offset)
  $offset += $dib.Length
}
foreach ($dib in $entries) { $bw.Write([byte[]]$dib) }
$bw.Close()
$fs.Close()
Write-Host ("wrote {0} ({1} bytes, {2} images)" -f $outPath, (Get-Item $outPath).Length, $count)
