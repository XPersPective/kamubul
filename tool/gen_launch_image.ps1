Add-Type -AssemblyName System.Drawing

$root = Split-Path -Parent $PSScriptRoot
$srcPath = Join-Path $root 'assets\brand\kamubul_icon.png'
$outDir = Join-Path $root 'ios\Runner\Assets.xcassets\LaunchImage.imageset'
$src = [System.Drawing.Image]::FromFile($srcPath)

function Write-Icon([int]$size, [string]$name) {
  $bmp = New-Object System.Drawing.Bitmap $size, $size
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
  $g.DrawImage($src, 0, 0, $size, $size)
  $bmp.Save((Join-Path $outDir $name), [System.Drawing.Imaging.ImageFormat]::Png)
  $g.Dispose()
  $bmp.Dispose()
}

# Storyboard imageView 168x185pt içinde ortalanır; ikon kare ve çerçeveye sığar.
Write-Icon 160 'LaunchImage.png'
Write-Icon 320 'LaunchImage@2x.png'
Write-Icon 480 'LaunchImage@3x.png'
$src.Dispose()
Write-Output 'LaunchImage set regenerated from brand icon.'
