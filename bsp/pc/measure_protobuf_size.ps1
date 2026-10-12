# 统计 protobuf 组件（components/serialization/protobuf/luat_lib_protobuf.c）在
# ARM -Os 下的静态占用，对比 LUAT_PROTOBUF_FULL_OPTIONS 开关的效果。
#
# 度量口径：单编译单元 + 链接期 --gc-sections，只统计 luaopen_protobuf 可达的
# .text + .rodata（即真正会进 flash 的部分），单位字节。
#   - 编译：arm-none-eabi-gcc -Os -mcpu=cortex-m4 -mthumb -ffunction-sections -fdata-sections
#   - 链接：-nostdlib -Wl,--gc-sections -Wl,-e,luaopen_protobuf -Wl,--unresolved-symbols=ignore-all
# 不同芯片（Cortex-M4 / RISC-V）绝对值会有差异，但开关的相对收益一致。
# 用相对路径编译：pb.h 的 assert 会把 __FILE__ 打进 .rodata，绝对路径会多几十字节。
#
# 用法: pwsh bsp/pc/measure_protobuf_size.ps1 [-Cpu cortex-m4]
param(
    [string]$Cpu = "cortex-m4",
    [string]$RepoRoot = ""
)
$ErrorActionPreference = "Stop"

function Find-ArmGcc {
    $cmd = Get-Command arm-none-eabi-gcc -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $roots = @("C:\Program Files (x86)\Arm GNU Toolchain arm-none-eabi", "C:\Program Files\Arm GNU Toolchain arm-none-eabi")
    foreach ($r in $roots) {
        if (Test-Path $r) {
            $hit = Get-ChildItem $r -Recurse -Filter arm-none-eabi-gcc.exe -ErrorAction SilentlyContinue |
                   Sort-Object FullName -Descending | Select-Object -First 1
            if ($hit) { return $hit.FullName }
        }
    }
    return $null
}

$gcc = Find-ArmGcc
if (-not $gcc) {
    Write-Error "未找到 arm-none-eabi-gcc，请安装 ARM GNU Toolchain 或将其加入 PATH"
    exit 1
}
$bin = Split-Path $gcc -Parent
$size = Join-Path $bin "arm-none-eabi-size.exe"

if (-not $RepoRoot) { $RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent }
$src = "components/serialization/protobuf/luat_lib_protobuf.c"
$tmp = Join-Path $env:TEMP "pb_measure"
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

$inc = @(
    "-Icomponents/serialization/protobuf",
    "-Iluat/include",
    "-Ilua/include",
    "-Ibsp/pc/include",
    "-Icomponents/printf"
)

# 档位：名字 -> 宏定义
$presets = [ordered]@{
    "FULL_OPTIONS=1 (原样保留运行时开关)" = @("-DLUAT_PROTOBUF_FULL_OPTIONS=1")
    "默认 (FULL_OPTIONS=0, 固化为常量)"   = @()
}

$obj = Join-Path $tmp "pb.o"
$elf = Join-Path $tmp "pb.elf"
$rows = @()
$baseline = 0
Push-Location $RepoRoot
try {
    foreach ($name in $presets.Keys) {
        $defs = $presets[$name]
        Remove-Item $obj, $elf -ErrorAction SilentlyContinue
        & $gcc -Os "-mcpu=$Cpu" -mthumb -std=gnu99 -D__LUATOS__ -ffunction-sections -fdata-sections @defs @inc -c $src -o $obj
        if ($LASTEXITCODE -ne 0) { throw "编译失败: $name" }
        & $gcc -Os "-mcpu=$Cpu" -mthumb -nostdlib "-Wl,--gc-sections" "-Wl,-e,luaopen_protobuf" `
            "-Wl,--unresolved-symbols=ignore-all" -o $elf $obj
        if ($LASTEXITCODE -ne 0) { throw "链接失败: $name" }
        $text = (& $size $elf | Select-Object -Last 1) -split '\s+' | Where-Object { $_ -ne '' } | Select-Object -First 1
        $text = [int]$text
        if ($baseline -eq 0) { $baseline = $text }
        $rows += [pscustomobject]@{ 档位 = $name; 字节 = $text; 相对基线 = $text - $baseline }
    }
} finally {
    Pop-Location
}
$rows | Format-Table -AutoSize
Write-Host ("基线(FULL_OPTIONS=1) = {0}B；默认配置 {1}B，省 {2}B" -f `
    $baseline, $rows[1].字节, ($baseline - $rows[1].字节))
