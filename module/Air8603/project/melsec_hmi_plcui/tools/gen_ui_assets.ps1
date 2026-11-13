#requires -Version 5.1
<#
生成 melsec_hmi_plcui 的界面素材（PNG）。
依赖 Windows 自带的 System.Drawing，无需 Python / Pillow。
用法：
  powershell -NoProfile -ExecutionPolicy Bypass -File tools\gen_ui_assets.ps1
输出：code\ui\img\*.png
#>
Add-Type -AssemblyName System.Drawing

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$out = Join-Path $root "code\ui\img"
New-Item -ItemType Directory -Force -Path $out | Out-Null

function ColorOf([string]$hex, [int]$alpha = 255) {
    $c = [System.Drawing.ColorTranslator]::FromHtml($hex)
    if ($alpha -eq 255) { return $c }
    return [System.Drawing.Color]::FromArgb($alpha, $c.R, $c.G, $c.B)
}

function RoundPath([single]$x, [single]$y, [single]$w, [single]$h, [single]$r) {
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    if ($r -le 0) {
        $p.AddRectangle((New-Object System.Drawing.RectangleF($x, $y, $w, $h)))
        return $p
    }
    $d = [single]($r * 2)
    $p.AddArc($x, $y, $d, $d, 180, 90)
    $p.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
    $p.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90)
    $p.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
    $p.CloseFigure()
    return $p
}

function New-Canvas([int]$w, [int]$h, [bool]$opaque = $false) {
    if ($opaque) {
        $bmp = New-Object System.Drawing.Bitmap($w, $h, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
    } else {
        $bmp = New-Object System.Drawing.Bitmap($w, $h, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    }
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    if ($opaque) {
        $g.Clear((ColorOf "#080E18"))
    } else {
        $g.Clear([System.Drawing.Color]::Transparent)
    }
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAlias
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    return @{ bmp = $bmp; g = $g }
}

function Save-Png($canvas, [string]$name) {
    $path = Join-Path $out $name
    $canvas.bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $canvas.g.Dispose()
    $canvas.bmp.Dispose()
    Write-Output ("  " + $name)
}

function FontOf([single]$size, [bool]$bold = $false) {
    if ($bold) {
        return New-Object System.Drawing.Font("Microsoft YaHei", $size, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
    }
    return New-Object System.Drawing.Font("Microsoft YaHei", $size, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
}

function Draw-Text($g, [string]$text, [single]$size, [string]$color, [single]$x, [single]$y, [single]$w, [single]$h, [string]$align = "center", [bool]$bold = $false) {
    $font = FontOf $size $bold
    $brush = New-Object System.Drawing.SolidBrush((ColorOf $color))
    $rect = New-Object System.Drawing.RectangleF($x, $y, $w, $h)
    $sf = New-Object System.Drawing.StringFormat
    $sf.FormatFlags = [System.Drawing.StringFormatFlags]::NoWrap
    $sf.LineAlignment = [System.Drawing.StringAlignment]::Center
    if ($align -eq "left") {
        $sf.Alignment = [System.Drawing.StringAlignment]::Near
    } elseif ($align -eq "right") {
        $sf.Alignment = [System.Drawing.StringAlignment]::Far
    } else {
        $sf.Alignment = [System.Drawing.StringAlignment]::Center
    }
    $g.DrawString($text, $font, $brush, $rect, $sf)
    $sf.Dispose()
    $brush.Dispose()
    $font.Dispose()
}

function Draw-RoundRect($g, [single]$x, [single]$y, [single]$w, [single]$h, [single]$r, [string]$fill, [string]$border, [single]$bw = 1) {
    $p = RoundPath $x $y $w $h $r
    if ($fill) {
        $b = New-Object System.Drawing.SolidBrush((ColorOf $fill))
        $g.FillPath($b, $p)
        $b.Dispose()
    }
    if ($border -and $bw -gt 0) {
        $pen = New-Object System.Drawing.Pen((ColorOf $border), $bw)
        $g.DrawPath($pen, $p)
        $pen.Dispose()
    }
    $p.Dispose()
}

function Draw-GradRect($g, [single]$x, [single]$y, [single]$w, [single]$h, [single]$r, [string]$c1, [string]$c2, [string]$border, [single]$bw = 1) {
    $p = RoundPath $x $y $w $h $r
    $rect = New-Object System.Drawing.RectangleF($x, $y, $w, $h)
    $b = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect, (ColorOf $c1), (ColorOf $c2), [System.Drawing.Drawing2D.LinearGradientMode]::Vertical)
    $g.FillPath($b, $p)
    $b.Dispose()
    if ($border -and $bw -gt 0) {
        $pen = New-Object System.Drawing.Pen((ColorOf $border), $bw)
        $g.DrawPath($pen, $p)
        $pen.Dispose()
    }
    $p.Dispose()
}

function Draw-Icon($g, [string]$kind, [single]$cx, [single]$cy, [string]$color) {
    $pen = New-Object System.Drawing.Pen((ColorOf $color), [single]2.2)
    $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    $brush = New-Object System.Drawing.SolidBrush((ColorOf $color))
    switch ($kind) {
        "gauge" {
            $g.DrawArc($pen, $cx - 11, $cy - 9, 22, 22, 180, 180)
            $g.DrawLine($pen, $cx, $cy + 1, $cx + 7, $cy - 7)
            $g.FillEllipse($brush, $cx - 2, $cy - 1, 4, 4)
        }
        "trend" {
            $g.DrawLine($pen, $cx - 11, $cy - 10, $cx - 11, $cy + 9)
            $g.DrawLine($pen, $cx - 11, $cy + 9, $cx + 11, $cy + 9)
            $pts = @(
                [System.Drawing.PointF]::new($cx - 8, $cy + 4)
                [System.Drawing.PointF]::new($cx - 2, $cy - 4)
                [System.Drawing.PointF]::new($cx + 3, $cy + 1)
                [System.Drawing.PointF]::new($cx + 10, $cy - 8)
            )
            $g.DrawLines($pen, [System.Drawing.PointF[]]$pts)
        }
        "bell" {
            $p = New-Object System.Drawing.Drawing2D.GraphicsPath
            $p.AddArc($cx - 9, $cy - 12, 18, 18, 180, 180)
            $p.AddLine($cx + 9, $cy - 3, $cx + 10, $cy + 3)
            $p.AddLine($cx + 10, $cy + 3, $cx - 10, $cy + 3)
            $p.AddLine($cx - 10, $cy + 3, $cx - 9, $cy - 3)
            $p.CloseFigure()
            $g.DrawPath($pen, $p)
            $p.Dispose()
            $g.DrawArc($pen, $cx - 3, $cy + 4, 6, 5, 0, 180)
        }
        "gear" {
            $g.DrawEllipse($pen, $cx - 8, $cy - 8, 16, 16)
            $g.DrawEllipse($pen, $cx - 3, $cy - 3, 6, 6)
            for ($i = 0; $i -lt 8; $i++) {
                $a = $i * [Math]::PI / 4
                $x1 = $cx + [Math]::Cos($a) * 9
                $y1 = $cy + [Math]::Sin($a) * 9
                $x2 = $cx + [Math]::Cos($a) * 12
                $y2 = $cy + [Math]::Sin($a) * 12
                $g.DrawLine($pen, [single]$x1, [single]$y1, [single]$x2, [single]$y2)
            }
        }
        "device" {
            $g.DrawRectangle($pen, $cx - 12, $cy - 8, 24, 16)
            $g.DrawLine($pen, $cx - 8, $cy - 3, $cx + 8, $cy - 3)
            $g.DrawLine($pen, $cx - 8, $cy + 2, $cx + 8, $cy + 2)
            $g.FillEllipse($brush, $cx + 4, $cy + 6, 3, 3)
        }
        "speaker" {
            $p = New-Object System.Drawing.Drawing2D.GraphicsPath
            $pts = @(
                [System.Drawing.PointF]::new($cx - 10, $cy - 3)
                [System.Drawing.PointF]::new($cx - 5, $cy - 3)
                [System.Drawing.PointF]::new($cx, $cy - 8)
                [System.Drawing.PointF]::new($cx, $cy + 8)
                [System.Drawing.PointF]::new($cx - 5, $cy + 3)
                [System.Drawing.PointF]::new($cx - 10, $cy + 3)
            )
            $p.AddPolygon([System.Drawing.PointF[]]$pts)
            $g.FillPath($brush, $p)
            $p.Dispose()
            $g.DrawArc($pen, $cx - 1, $cy - 6, 10, 12, -55, 110)
            $g.DrawArc($pen, $cx - 1, $cy - 10, 18, 20, -55, 110)
        }
        "speaker_off" {
            $p = New-Object System.Drawing.Drawing2D.GraphicsPath
            $pts = @(
                [System.Drawing.PointF]::new($cx - 10, $cy - 3)
                [System.Drawing.PointF]::new($cx - 5, $cy - 3)
                [System.Drawing.PointF]::new($cx, $cy - 8)
                [System.Drawing.PointF]::new($cx, $cy + 8)
                [System.Drawing.PointF]::new($cx - 5, $cy + 3)
                [System.Drawing.PointF]::new($cx - 10, $cy + 3)
            )
            $p.AddPolygon([System.Drawing.PointF[]]$pts)
            $g.FillPath($brush, $p)
            $p.Dispose()
            $g.DrawLine($pen, $cx + 3, $cy - 7, $cx + 12, $cy + 7)
        }
    }
    $brush.Dispose()
    $pen.Dispose()
}

# ---------------- 背景 / Logo / 状态灯 ----------------
Write-Output "背景与标识："

$c = New-Canvas 8 600 $true
$rect = New-Object System.Drawing.RectangleF(0, 0, 8, 600)
$b = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect, (ColorOf "#080E18"), (ColorOf "#111A28"), [System.Drawing.Drawing2D.LinearGradientMode]::Vertical)
$c.g.FillRectangle($b, $rect)
$b.Dispose()
Save-Png $c "bg.png"

$c = New-Canvas 40 40
$p = RoundPath 0.5 0.5 39 39 10
$rect = New-Object System.Drawing.RectangleF(0, 0, 40, 40)
$b = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect, (ColorOf "#22D3EE"), (ColorOf "#0891B2"), [System.Drawing.Drawing2D.LinearGradientMode]::Vertical)
$c.g.FillPath($b, $p)
$b.Dispose()
$pen = New-Object System.Drawing.Pen((ColorOf "#7DD3FC" 120), [single]1)
$c.g.DrawPath($pen, $p)
$pen.Dispose()
$p.Dispose()
Draw-Text $c.g "FX" 16 "#04121C" 0 0 40 40 "center" $true
Save-Png $c "logo.png"

function New-Dot([string]$name, [string]$color) {
    $c = New-Canvas 12 12
    $glow = New-Object System.Drawing.SolidBrush((ColorOf $color 70))
    $c.g.FillEllipse($glow, 0, 0, 12, 12)
    $glow.Dispose()
    $core = New-Object System.Drawing.SolidBrush((ColorOf $color))
    $c.g.FillEllipse($core, 2.5, 2.5, 7, 7)
    $core.Dispose()
    Save-Png $c $name
}

New-Dot "dot_online.png" "#3DDC97"
New-Dot "dot_offline.png" "#FF5A5F"

# ---------------- 状态胶囊 ----------------
Write-Output "状态胶囊："

function New-Pill([string]$name, [string]$color, [string]$text, [string]$textColor) {
    $c = New-Canvas 96 28
    $p = RoundPath 0.5 0.5 95 27 13.5
    $b = New-Object System.Drawing.SolidBrush((ColorOf $color 42))
    $c.g.FillPath($b, $p)
    $b.Dispose()
    $pen = New-Object System.Drawing.Pen((ColorOf $color), [single]1)
    $c.g.DrawPath($pen, $p)
    $pen.Dispose()
    $p.Dispose()
    $dot = New-Object System.Drawing.SolidBrush((ColorOf $color))
    $c.g.FillEllipse($dot, 11, 11, 6, 6)
    $dot.Dispose()
    Draw-Text $c.g $text 13 $textColor 20 0 70 28 "left"
    Save-Png $c $name
}

New-Pill "pill_normal.png" "#3DDC97" "正常" "#7CF0C0"
New-Pill "pill_warn.png" "#FFB020" "预警" "#FFD37A"
New-Pill "pill_alarm.png" "#FF5A5F" "报警" "#FF9A9D"

# ---------------- 左侧导航 ----------------
Write-Output "导航按钮："

function New-Nav([string]$name, [string]$kind, [string]$text) {
    $states = @()
    $states += @{ bg1 = "#0F1A2B"; bg2 = "#0C1626"; border = "#1B2C46"; fg = "#8FA3BF"; accent = $false }
    $states += @{ bg1 = "#16263D"; bg2 = "#132238"; border = "#2C4767"; fg = "#C9D6E8"; accent = $false }
    $states += @{ bg1 = "#0F2C3C"; bg2 = "#0B2230"; border = "#22D3EE"; fg = "#22D3EE"; accent = $true }
    $suffix = @("n", "p", "c")
    for ($i = 0; $i -lt 3; $i++) {
        $s = $states[$i]
        $c = New-Canvas 76 84
        Draw-GradRect $c.g 0.5 0.5 75 83 12 $s.bg1 $s.bg2 $s.border 1
        if ($s.accent) {
            $bar = New-Object System.Drawing.SolidBrush((ColorOf "#22D3EE"))
            $c.g.FillRectangle($bar, 2, 26, 3, 32)
            $bar.Dispose()
        }
        Draw-Icon $c.g $kind 38 28 $s.fg
        Draw-Text $c.g $text 13 $s.fg 0 48 76 24 "center"
        Save-Png $c ("btn_nav_{0}_{1}.png" -f $name, $suffix[$i])
    }
}

New-Nav "dash" "gauge" "总览"
New-Nav "trend" "trend" "趋势"
New-Nav "alarm" "bell" "报警"
New-Nav "dev" "device" "设备"
New-Nav "set" "gear" "设置"

# ---------------- 通用按钮 ----------------
Write-Output "功能按钮："

function New-Btn([string]$name, [int]$w, [int]$h, [string]$text, [single]$fs, $style) {
    $states = @("n", "p", "c")
    foreach ($k in $states) {
        if (-not $style.ContainsKey($k)) { continue }
        $s = $style[$k]
        $c = New-Canvas $w $h
        if ($s.bg1 -eq $s.bg2) {
            Draw-RoundRect $c.g 0.5 0.5 ($w - 1) ($h - 1) ([single]($style.radius)) $s.bg1 $s.border 1
        } else {
            Draw-GradRect $c.g 0.5 0.5 ($w - 1) ($h - 1) ([single]($style.radius)) $s.bg1 $s.bg2 $s.border 1
        }
        Draw-Text $c.g $text $fs $s.text 0 0 $w $h "center" ([bool]$style.bold)
        Save-Png $c ("{0}_{1}.png" -f $name, $k)
    }
}

$styleSecondary = @{
    radius = 8; bold = $false
    n = @{ bg1 = "#152031"; bg2 = "#152031"; border = "#2A3F5C"; text = "#C9D6E8" }
    p = @{ bg1 = "#1E3350"; bg2 = "#1E3350"; border = "#3A5678"; text = "#FFFFFF" }
}
$stylePrimary = @{
    radius = 8; bold = $true
    n = @{ bg1 = "#22D3EE"; bg2 = "#0EA5B7"; border = "#67E8F9"; text = "#04121C" }
    p = @{ bg1 = "#0EA5B7"; bg2 = "#0891B2"; border = "#22D3EE"; text = "#04121C" }
}
$styleDanger = @{
    radius = 8; bold = $true
    n = @{ bg1 = "#FFB020"; bg2 = "#F59E0B"; border = "#FFD37A"; text = "#241500" }
    p = @{ bg1 = "#F59E0B"; bg2 = "#D97706"; border = "#FFB020"; text = "#241500" }
}

New-Btn "btn_save" 160 48 "保存设置" 16 $stylePrimary
New-Btn "btn_default" 210 48 "恢复默认 70%/90%" 14 $styleSecondary
New-Btn "btn_test" 150 48 "声音测试" 15 $styleSecondary

New-Btn "btn_ack" 112 40 "报警复位" 14 $styleDanger
New-Btn "btn_logclear" 112 40 "清空记录" 14 $styleSecondary

$styleMute = @{
    radius = 8; bold = $false
    n = @{ bg1 = "#152031"; bg2 = "#152031"; border = "#2A3F5C"; text = "#C9D6E8" }
    c = @{ bg1 = "#3A2A0E"; bg2 = "#3A2A0E"; border = "#FFB020"; text = "#FFD37A" }
}
New-Btn "btn_mute" 112 40 "消音" 14 $styleMute

$styleMinus = @{
    radius = 8; bold = $false
    n = @{ bg1 = "#152031"; bg2 = "#152031"; border = "#2A3F5C"; text = "#E9F1FB" }
    p = @{ bg1 = "#1E3350"; bg2 = "#1E3350"; border = "#3A5678"; text = "#FFFFFF" }
}
New-Btn "btn_step_down" 52 40 "-" 22 $styleMinus
New-Btn "btn_step_up" 52 40 "+" 22 $styleMinus

$styleCh1 = @{
    radius = 8; bold = $false
    n = @{ bg1 = "#152031"; bg2 = "#152031"; border = "#2A3F5C"; text = "#8FA3BF" }
    c = @{ bg1 = "#0F2C3C"; bg2 = "#0B2230"; border = "#22D3EE"; text = "#22D3EE" }
}
$styleCh2 = @{
    radius = 8; bold = $false
    n = @{ bg1 = "#152031"; bg2 = "#152031"; border = "#2A3F5C"; text = "#8FA3BF" }
    c = @{ bg1 = "#101F3C"; bg2 = "#0C1830"; border = "#4C8DFF"; text = "#4C8DFF" }
}
New-Btn "btn_ch1" 96 36 "温度 1" 13 $styleCh1
New-Btn "btn_ch2" 96 36 "温度 2" 13 $styleCh2
New-Btn "btn_clear" 204 36 "清空曲线" 13 $styleSecondary

# ---------------- 顶部声音按钮 ----------------
Write-Output "顶部按钮："

function New-SoundButton([string]$name, [bool]$muted) {
    $c = New-Canvas 40 40
    if ($muted) {
        Draw-RoundRect $c.g 0.5 0.5 39 39 10 "#3A2A0E" "#FFB020" 1
        Draw-Icon $c.g "speaker_off" 20 20 "#FFD37A"
    } else {
        Draw-RoundRect $c.g 0.5 0.5 39 39 10 "#152031" "#2A3F5C" 1
        Draw-Icon $c.g "speaker" 20 20 "#9FB0C7"
    }
    Save-Png $c $name
}

New-SoundButton "btn_sound_n.png" $false
New-SoundButton "btn_sound_c.png" $true

Write-Output "完成，输出目录：$out"
