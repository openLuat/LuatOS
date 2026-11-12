# 生成链路流光帧：调用 tools/anim.html 渲染 n 帧竖排大图，再按行裁成 n 张透明 PNG。
# 用法： powershell -File tools\gen_anim.ps1 -W 104 -H 28 -N 8 -Dir ltr -Color 22D3EE -Prefix flow_485a
param(
    [int]$W = 104,
    [int]$H = 28,
    [int]$N = 8,
    [string]$Dir = "ltr",
    [string]$Color = "22D3EE",
    [string]$Prefix = "flow_485a",
    [string]$Out = "",
    [switch]$Solid
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
if ($Out -eq "") { $Out = Join-Path $root "code\ui\img" }
$html = Join-Path $PSScriptRoot "anim.html"

$edge = "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
if (-not (Test-Path $edge)) { $edge = "C:\Program Files\Microsoft\Edge\Application\msedge.exe" }
if (-not (Test-Path $edge)) { throw "Edge not found" }

$shot = Join-Path $env:TEMP ("anim_" + $Prefix + ".png")
$uri = "file:///" + $html.Replace('\', '/') + "?w=$W&h=$H&n=$N&dir=$Dir&c=$Color"

$edgeArgs = @(
    '--headless=new', '--disable-gpu', '--hide-scrollbars', '--no-first-run',
    '--force-device-scale-factor=1', "--window-size=$W,$($H * $N)",
    "--screenshot=$shot", $uri
)
if ($Solid) { $edgeArgs = @('--default-background-color=FF0B1220') + $edgeArgs }
else { $edgeArgs = @('--default-background-color=00000000') + $edgeArgs }

if (Test-Path $shot) { Remove-Item $shot -Force }
& $edge @edgeArgs | Out-Null
Start-Sleep -Milliseconds 600
if (-not (Test-Path $shot)) { throw "screenshot failed: $shot" }

Add-Type -AssemblyName System.Drawing
$src = [System.Drawing.Image]::FromFile($shot)
try {
    if ($src.Width -ne $W -or $src.Height -ne ($H * $N)) {
        throw ("unexpected shot size {0}x{1}, want {2}x{3}" -f $src.Width, $src.Height, $W, ($H * $N))
    }
    for ($i = 0; $i -lt $N; $i++) {
        $bmp = New-Object System.Drawing.Bitmap($W, $H, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $dstRect = New-Object System.Drawing.Rectangle(0, 0, $W, $H)
        $srcRect = New-Object System.Drawing.Rectangle(0, ($i * $H), $W, $H)
        $g.DrawImage($src, $dstRect, $srcRect, [System.Drawing.GraphicsUnit]::Pixel)
        $g.Dispose()
        $file = Join-Path $Out ("{0}_{1}.png" -f $Prefix, ($i + 1))
        $bmp.Save($file, [System.Drawing.Imaging.ImageFormat]::Png)
        $bmp.Dispose()
    }
}
finally { $src.Dispose() }

$files = Get-ChildItem (Join-Path $Out ($Prefix + "_*.png"))
"{0}  frames={1}  total={2} KB" -f $Prefix, $files.Count, [int](($files | Measure-Object Length -Sum).Sum / 1024)
