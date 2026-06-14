# setup_com0com_pair.ps1
#
# 创建 com0com 虚拟串口对 (CNCA0 <-> CNCB0)
# Windows 上 setupc.exe 默认安装在 C:\Program Files (x86)\com0com\
# 64-bit Windows: C:\Program Files\com0com\
#
# 完成后可在设备管理器看到 COM5 / COM6 端口

$ErrorActionPreference = "Stop"

$setupPaths = @(
    "C:\Program Files\com0com\setupc.exe",
    "C:\Program Files (x86)\com0com\setupc.exe"
)

$setupc = $null
foreach ($p in $setupPaths) {
    if (Test-Path $p) { $setupc = $p; break }
}

if (-not $setupc) {
    Write-Host "[FATAL] 未找到 setupc.exe, 请先安装 com0com:" -ForegroundColor Red
    Write-Host "  https://sourceforge.net/projects/com0com/" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "也可以手动运行 PowerShell (管理员模式):" -ForegroundColor Cyan
    Write-Host "  1. 从 sourceforge 下载 com0com 并安装"
    Write-Host "  2. 启动 setupc.exe GUI, 创建 CNCA0 <-> CNCB0"
    Write-Host "  3. 重新运行此脚本"
    exit 2
}

Write-Host "使用 setupc: $setupc"

# 列出已存在的对
Write-Host ""
Write-Host "已存在的 com0com 对:"
& $setupc list 2>&1 | Out-Host

# 创建 COM5 <-> COM6 对(若已存在则跳过)
$PAIR_EXISTS = (& $setupc list 2>&1) -match "CNC[AB]0.*COM5|COM5.*CNC[AB]0"
if ($PAIR_EXISTS) {
    Write-Host "COM5 <-> COM6 对已存在, 跳过创建" -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "创建 COM5 <-> COM6 虚拟串口对..."
    # setupc install 5 6 5 表示: PortName=COM5, PortName=COM6, EmuParams=5(全仿真)
    & $setupc install 5 COM6 5
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[FATAL] 创建对失败, 退出码 $LASTEXITCODE" -ForegroundColor Red
        exit 1
    }
}

Write-Host ""
Write-Host "=== 当前 com0com 配置 ===" -ForegroundColor Cyan
& $setupc list 2>&1 | Out-Host

Write-Host ""
Write-Host "OK. 下一步:" -ForegroundColor Green
Write-Host "  1. 启动 LuatOS AT server:"
Write-Host "       cd bsp\pc\build\out"
Write-Host "       .\luatos-lua.exe ..\..\..\..\testcase\common\scripts\ \"
Write-Host "                     ..\..\..\..\tools\rfcal_com0com\at_server_main\"
Write-Host "  2. 在另一个终端跑回归脚本:"
Write-Host "       python tools\rfcal_com0com\test_rfcal_com0com.py --port COM5"
