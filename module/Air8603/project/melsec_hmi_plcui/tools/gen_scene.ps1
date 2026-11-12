<#
.SYNOPSIS
    把 tools/scene.html 渲染成 code/ui/img/dev_scene.png（896x496，透明底或深色底）。

.DESCRIPTION
    用 Edge 无头模式截图，免装 Inkscape / ImageMagick。
    页面坐标与 dev 页的偏移关系见 scene.html 头部注释。
    改完 scene.html 重跑本脚本即可，不要在设备端手改 PNG。

.PARAMETER Opacity
    true（默认）输出透明底 PNG；false 则铺纯色 #0B1220 便于本地看图。

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools\gen_scene.ps1
#>
param(
    [switch]$Solid
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$html = Join-Path $PSScriptRoot 'scene.html'
$out  = Join-Path $root 'code\ui\img\dev_scene.png'

if (-not (Test-Path $html)) { throw "缺少 scene.html：$html" }

$edge = @(
    'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe',
    'C:\Program Files\Microsoft\Edge\Application\msedge.exe',
    'C:\Program Files\Google\Chrome\Application\chrome.exe'
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $edge) { throw '找不到 Edge / Chrome，无法截图' }

$uri = 'file:///' + ($html -replace '\\', '/')
$edgeArgs = @(
    '--headless=new', '--disable-gpu', '--hide-scrollbars', '--no-first-run',
    '--force-device-scale-factor=1', '--window-size=896,496',
    "--screenshot=$out", $uri
)
if ($Solid) { $edgeArgs = @('--default-background-color=FF0B1220') + $edgeArgs }
else { $edgeArgs = @('--default-background-color=00000000') + $edgeArgs }

if (Test-Path $out) { Remove-Item $out -Force }
& $edge @edgeArgs | Out-Null
Start-Sleep -Milliseconds 1200

if (-not (Test-Path $out)) { throw '截图失败，未生成 PNG' }

Add-Type -AssemblyName System.Drawing
$img = [System.Drawing.Image]::FromFile($out)
$size = '{0}x{1}' -f $img.Width, $img.Height
$img.Dispose()
$kb = [int]((Get-Item $out).Length / 1024)
Write-Host "生成 $out  $size  ${kb} KB"
