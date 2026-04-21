# test_dep_strip_llt.ps1
# 集成测试: 验证 --llt= 与位置参数目录在依赖裁剪(dep_strip)模式下的联合分析
# 运行方式: cd bsp/pc && .\test_dep_strip_llt.ps1
# 需要先构建 GUI 版本: .\build_windows_64bit_msvc_gui.bat

param(
    [string]$Exe = "$PSScriptRoot\build\out\luatos-lua.exe"
)

$ErrorActionPreference = "Stop"

# Resolve exe to absolute path so it stays valid after Push-Location
$Exe = (Resolve-Path $Exe).Path

# ── 辅助函数 ──────────────────────────────────────────────────────────────────

function Fail([string]$msg) {
    Write-Host "FAIL: $msg" -ForegroundColor Red
    exit 1
}

function Pass([string]$msg) {
    Write-Host "PASS: $msg" -ForegroundColor Green
}

# 解析 luadb2 二进制格式, 返回其中所有文件名列表
# luadb2 格式:
#   全局头: magic(6) + version(4) + headers_size(6) + file_count(4) + crc(4)
#   每个文件: magic(6) + name_tag(1)+name_len(1)+name(n) + size_tag(1)+size_tag2(1)+size(4) + crc(4) + data(size)
function Get-LuadbFiles([string]$path) {
    $bytes = [System.IO.File]::ReadAllBytes($path)
    $files = @()
    $pos = 0
    $len = $bytes.Length

    # 跳过全局头 (6+4+6+4+4 = 24 bytes)
    if ($len -lt 24) { return $files }
    $pos = 24

    while ($pos + 6 -lt $len) {
        # 每个文件以 magic 01 04 5A A5 5A A5 开头
        if ($bytes[$pos]   -ne 0x01 -or $bytes[$pos+1] -ne 0x04 -or
            $bytes[$pos+2] -ne 0x5A -or $bytes[$pos+3] -ne 0xA5 -or
            $bytes[$pos+4] -ne 0x5A -or $bytes[$pos+5] -ne 0xA5) {
            break
        }
        $pos += 6
        # name tag (0x02) + name_len(1 byte) + name
        if ($pos + 2 -gt $len) { break }
        $nameLen = $bytes[$pos + 1]
        $pos += 2
        if ($pos + $nameLen -gt $len) { break }
        $name = [System.Text.Encoding]::UTF8.GetString($bytes, $pos, $nameLen)
        $files += $name
        $pos += $nameLen
        # size tag (0x03) + 0x04 + size(4 bytes LE)
        if ($pos + 6 -gt $len) { break }
        $dataSize = [BitConverter]::ToUInt32($bytes, $pos + 2)
        $pos += 6
        # crc tag (0xFE) + 0x02 + 2 bytes
        if ($pos + 4 -gt $len) { break }
        $pos += 4
        # data
        $pos += [int]$dataSize
    }
    return $files
}

# ── 检查二进制 ────────────────────────────────────────────────────────────────

if (-not (Test-Path $Exe)) {
    Fail "找不到模拟器二进制: $Exe`n请先运行 build_windows_64bit_msvc_gui.bat"
}

# ── 构建测试夹具 ──────────────────────────────────────────────────────────────

$TestBase = "$PSScriptRoot\tmp\test_dep_strip_llt"
if (Test-Path $TestBase) { Remove-Item -Recurse -Force $TestBase }
New-Item -ItemType Directory -Force -Path $TestBase | Out-Null

$ProjectDir = "$TestBase\project"
$LibDir     = "$TestBase\lib"
New-Item -ItemType Directory -Force -Path $ProjectDir | Out-Null
New-Item -ItemType Directory -Force -Path $LibDir     | Out-Null

# project/main.lua — 入口, 依赖 mod_a 和 mod_shared
Set-Content "$ProjectDir\main.lua" @'
PROJECT = "deptest"
VERSION = "1.0.0"
require "mod_a"
require "mod_shared"
sys = sys or {}
function sys.run() end
'@

# project/mod_shared.lua — main.lua 和 mod_a 都需要
Set-Content "$ProjectDir\mod_shared.lua" @'
-- shared helper
'@

# lib/mod_a.lua — 源码
Set-Content "$LibDir\mod_a.lua" @'
require "mod_shared"
'@

# lib/mod_a.luac — 模拟预编译产物 (内容随意, 测试路由逻辑; 实际环境中应为真实 luac)
# 用一个合法的空 luadb-dummy 文件占位, 文件名以 .luac 结尾即可被识别为二进制产物
Set-Content "$LibDir\mod_a.luac" "LUAC_PLACEHOLDER"

# lib/mod_b.lua — 未被任何人引用, 应被裁剪
Set-Content "$LibDir\mod_b.lua" @'
-- this module is NOT required by anyone
'@

# lib/mod_b.luac — 同上
Set-Content "$LibDir\mod_b.luac" "LUAC_PLACEHOLDER"

# lib/extra_resource.txt — 非 lua 资源文件, 应始终被保留
Set-Content "$LibDir\extra_resource.txt" "resource data"

# INI 文件: 描述项目中的文件
$IniContent = @"
[info]
[$ProjectDir]
main.lua = 0
mod_shared.lua = 0
"@
Set-Content "$TestBase\test.ini" $IniContent

# ── 运行测试 ──────────────────────────────────────────────────────────────────

$OutDb = "$TestBase\output.ldb"

Write-Host ""
Write-Host "=== 测试 1: --llt= + 位置参数目录, dep_strip=1 (默认) ===" -ForegroundColor Cyan

$args1 = @(
    "$LibDir\",
    "--llt=$TestBase\test.ini",
    "--norun=1",
    "--dep_strip=1",
    "--dump_luadb=$OutDb"
)
Write-Host "命令: $Exe $($args1 -join ' ')"
& $Exe @args1
if ($LASTEXITCODE -ne 0) { Fail "模拟器退出码 $LASTEXITCODE" }
if (-not (Test-Path $OutDb)) { Fail "output.ldb 未生成" }

$files = Get-LuadbFiles $OutDb
Write-Host "luadb 中的文件: $($files -join ', ')"

# main.lua 会被编译为 luac, luadb 中存储的名称仍是 main.lua (add_onefile 用 basename)
if ($files -notcontains "main.lua") { Fail "main.lua 应在 luadb 中" }
Pass "main.lua 存在"

# mod_shared.lua 被 main.lua 和 mod_a 依赖
if ($files -notcontains "mod_shared.lua") { Fail "mod_shared.lua 应在 luadb 中" }
Pass "mod_shared.lua 存在"

# 资源文件始终保留
if ($files -notcontains "extra_resource.txt") { Fail "extra_resource.txt 应在 luadb 中" }
Pass "extra_resource.txt 存在"

# mod_b.lua 和 mod_b.luac 均未被引用, 应被裁剪
if ($files -contains "mod_b.lua")  { Fail "mod_b.lua 应被裁剪 (dep_strip)" }
Pass "mod_b.lua 被裁剪"

if ($files -contains "mod_b.luac") { Fail "mod_b.luac 应被裁剪 (dep_strip)" }
Pass "mod_b.luac 被裁剪"

# ── 测试 2: dep_strip=0 时应全量打包 ─────────────────────────────────────────

Write-Host ""
Write-Host "=== 测试 2: dep_strip=0, 全量打包 ===" -ForegroundColor Cyan

$OutDb2 = "$TestBase\output2.ldb"
$args2 = @(
    "$LibDir\",
    "--llt=$TestBase\test.ini",
    "--norun=1",
    "--dep_strip=0",
    "--dump_luadb=$OutDb2"
)
Write-Host "命令: $Exe $($args2 -join ' ')"
& $Exe @args2
if ($LASTEXITCODE -ne 0) { Fail "模拟器退出码 $LASTEXITCODE (test2)" }
if (-not (Test-Path $OutDb2)) { Fail "output2.ldb 未生成" }

$files2 = Get-LuadbFiles $OutDb2
Write-Host "luadb 中的文件: $($files2 -join ', ')"

if ($files2 -notcontains "mod_b.lua")  { Fail "dep_strip=0 时 mod_b.lua 应全量保留" }
Pass "dep_strip=0: mod_b.lua 全量保留"

if ($files2 -notcontains "mod_b.luac") { Fail "dep_strip=0 时 mod_b.luac 应全量保留" }
Pass "dep_strip=0: mod_b.luac 全量保留"

# ── 测试 3: . (当前目录) 作为位置参数 ─────────────────────────────────────────

Write-Host ""
Write-Host "=== 测试 3: '.' 作为位置参数 ===" -ForegroundColor Cyan

$OutDb3 = "$TestBase\output3.ldb"
Push-Location $ProjectDir
try {
    $args3 = @(
        "$LibDir\",
        "--llt=$TestBase\test.ini",
        "--norun=1",
        "--dep_strip=1",
        "--dump_luadb=$OutDb3"
    )
    Write-Host "工作目录: $ProjectDir"
    Write-Host "命令: $Exe $($args3 -join ' ')"
    & $Exe @args3
    if ($LASTEXITCODE -ne 0) { Fail "模拟器退出码 $LASTEXITCODE (test3)" }
} finally {
    Pop-Location
}
if (-not (Test-Path $OutDb3)) { Fail "output3.ldb 未生成" }
$files3 = Get-LuadbFiles $OutDb3
Write-Host "luadb 中的文件: $($files3 -join ', ')"
if ($files3 -notcontains "main.lua") { Fail "test3: main.lua 应在 luadb 中" }
Pass "test3: main.lua 存在"

# ── 清理 & 汇总 ──────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "所有测试通过!" -ForegroundColor Green

