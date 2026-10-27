# 台词音频生成器（PC 上跑一次，产物提交进 res/voice/）
#
# 用途：固件没有本地 TTS 时，猫说的话靠这些 WAV 播放（app/voice.lua 路径 B）。
# 做法：用系统中文语音（Microsoft Huihui Desktop）把台词合成 16kHz/16bit/单声道 WAV，
#       再裁掉首尾静音（TTS 输出常有几百毫秒空白，裁掉能省 20% 体积）。
#
# 用法：powershell -ExecutionPolicy Bypass -File tools\make_voice_wav.ps1
#       改台词时，下面 $lines 和 ui/cat.lua 里 REGIONS 的 say 必须同步改。
#
# 注意：本文件必须保存成「UTF-8 带 BOM」，否则 PowerShell 5.1 会按 ANSI 读中文而报语法错误。
Add-Type -AssemblyName System.Speech

$outDir = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "..\res\voice"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$lines = [ordered]@{
    "head"  = "谢谢主人"
    "ear"   = "耳朵好痒"
    "eye"   = "别戳眼睛"
    "face"  = "主人你好"
    "belly" = "肚子好舒服"
    "paw"   = "手也摸摸"
    "foot"  = "脚脚怕痒"
    "tail"  = "别拽尾巴"
}

$fmt = New-Object System.Speech.AudioFormat.SpeechAudioFormatInfo(
    16000,
    [System.Speech.AudioFormat.AudioBitsPerSample]::Sixteen,
    [System.Speech.AudioFormat.AudioChannel]::Mono)

$synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
$synth.SelectVoice("Microsoft Huihui Desktop")
$synth.Rate = -1          # 稍慢一点，听起来更亲切
$synth.Volume = 90

function Trim-Wav([string]$path) {
    $bytes = [System.IO.File]::ReadAllBytes($path)
    # 找 data chunk（WAV 头里固定是小端 ASCII "data"）
    $dataOff = -1
    for ($i = 0; $i -lt [Math]::Min(200, $bytes.Length - 8); $i++) {
        if ($bytes[$i] -eq 0x64 -and $bytes[$i + 1] -eq 0x61 -and
            $bytes[$i + 2] -eq 0x74 -and $bytes[$i + 3] -eq 0x61) { $dataOff = $i; break }
    }
    if ($dataOff -lt 0) { throw "no data chunk: $path" }
    $pcmStart = $dataOff + 8
    $pcmLen = $bytes.Length - $pcmStart
    $n = [int]($pcmLen / 2)

    # 找首尾第一个超过阈值的采样
    $thr = 260
    $first = 0
    for ($i = 0; $i -lt $n; $i++) {
        $v = [BitConverter]::ToInt16($bytes, $pcmStart + $i * 2)
        if ([Math]::Abs($v) -gt $thr) { $first = $i; break }
    }
    $last = $n - 1
    for ($i = $n - 1; $i -ge 0; $i--) {
        $v = [BitConverter]::ToInt16($bytes, $pcmStart + $i * 2)
        if ([Math]::Abs($v) -gt $thr) { $last = $i; break }
    }
    # 两端各留 40ms 余量，避免把字头吃掉
    $pad = [int](0.04 * 16000)
    $first = [Math]::Max(0, $first - $pad)
    $last = [Math]::Min($n - 1, $last + $pad)

    $keep = ($last - $first + 1) * 2
    $out = New-Object byte[] ($pcmStart + $keep)
    [Array]::Copy($bytes, 0, $out, 0, $pcmStart)
    [Array]::Copy($bytes, $pcmStart + $first * 2, $out, $pcmStart, $keep)
    # 改 RIFF size 与 data size
    $riffSize = [BitConverter]::GetBytes([int]($out.Length - 8))
    [Array]::Copy($riffSize, 0, $out, 4, 4)
    $dataSize = [BitConverter]::GetBytes([int]$keep)
    [Array]::Copy($dataSize, 0, $out, $dataOff + 4, 4)
    [System.IO.File]::WriteAllBytes($path, $out)
    return @{ dur = ($keep / 2.0 / 16000.0); bytes = $out.Length }
}

$total = 0
foreach ($k in $lines.Keys) {
    $path = Join-Path $outDir ($k + ".wav")
    $synth.SetOutputToWaveFile($path, $fmt)
    $synth.Speak($lines[$k])
    $synth.SetOutputToNull()
    $r = Trim-Wav $path
    $total += $r.bytes
    Write-Output ("{0,-6} {1,-6} {2,7:N2}s {3,7} bytes" -f $k, $lines[$k], $r.dur, $r.bytes)
}
$synth.Dispose()
Write-Output ("total {0:N0} bytes" -f $total)
