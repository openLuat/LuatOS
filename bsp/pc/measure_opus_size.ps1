# 统计 opus 相关 .obj 的代码段体积 (.text$mn + .rdata)，按模块目录分组
# -Since 指定后只统计该时间之后编译的 obj（排除 xmake 不自动清理的孤儿 obj）
param(
    [string]$ObjsRoot = "C:\Users\wendal\.qoder-cn\worktree\LuatOS\luTEXa\bsp\pc\build\.objs",
    [string]$Since = ""
)

$db = "C:\Program Files\Microsoft Visual Studio\18\Community\VC\Tools\MSVC\14.51.36231\bin\Hostx64\x64\dumpbin.exe"
$objs = Get-ChildItem $ObjsRoot -Recurse -Filter *.obj | Where-Object FullName -match "multimedia\\opus"
if ($Since -ne "") {
    $cutoff = Get-Date $Since
    $stale = ($objs | Where-Object LastWriteTime -le $cutoff).Count
    $objs = $objs | Where-Object LastWriteTime -gt $cutoff
    Write-Output ("(filtered out $stale stale obj(s) older than $Since)")
}

$totals = @{}
$grandTotal = 0
$rows = @()

foreach ($o in $objs) {
    $out = & $db /SUMMARY $o.FullName
    $size = 0
    foreach ($line in $out) {
        # 形如 "        6950 .text$mn"：前缀十六进制大小 + 节名
        if ($line -match '^\s+([0-9A-Fa-f]+)\s+(\.[\w\$\?@]+)\s*$') {
            $name = $matches[2]
            if ($name -eq '.text$mn' -or $name -eq '.rdata') {
                $size += [Convert]::ToInt32($matches[1], 16)
            }
        }
    }
    $parent = Split-Path (Split-Path $o.FullName -Parent) -Leaf
    $selfDir = Split-Path $o.FullName -Parent | Split-Path -Leaf
    $module = switch ($selfDir) {
        "celt"  { if ($parent -eq "opus") { "celt" } else { "celt/arm" } }
        "silk"  { "silk" }
        "fixed" { "silk/fixed" }
        "src"   { "src" }
        "arm"   { "celt/arm" }
        default { "opus(root)" }
    }
    if (-not $totals.ContainsKey($module)) { $totals[$module] = 0 }
    $totals[$module] += $size
    $grandTotal += $size
    $rows += [pscustomobject]@{ Module = $module; Name = $o.Name; SizeKB = [math]::Round($size/1024, 2) }
}

Write-Output "=== opus obj size (.text + .rdata) ==="
Write-Output ("obj count: " + $objs.Count)
foreach ($k in ($totals.Keys | Sort-Object)) {
    Write-Output ("{0,-12} {1,8:N1} KB" -f $k, ($totals[$k]/1024))
}
Write-Output ("{0,-12} {1,8:N1} KB" -f "TOTAL", ($grandTotal/1024))
Write-Output ""
Write-Output "=== Top 15 files ==="
$rows | Sort-Object SizeKB -Descending | Select-Object -First 15 | Format-Table -AutoSize | Out-String
