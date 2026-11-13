param([string]$Path)

$ErrorActionPreference = "Stop"
$doc = New-Object System.Xml.XmlDocument
$doc.Load($Path)
$base = Split-Path -Parent $Path

$resIds = @{}
$missFile = @()
foreach ($n in $doc.SelectNodes("/ui/resources/image")) {
    $resIds[$n.GetAttribute("id")] = $true
    # 本地素材放在 ui/img/，下载时会拍平到脚本区根目录，所以两处都算数
    $src = $n.GetAttribute("src")
    $f = Join-Path $base $src
    if (-not (Test-Path $f)) { $f = Join-Path (Join-Path $base "ui/img") $src }
    if (-not (Test-Path $f)) { $missFile += $src }
}

$missRef = @()
foreach ($n in $doc.SelectNodes("//pages//image[@src]")) {
    foreach ($a in @("src", "src-pressed", "src-checked")) {
        $v = $n.GetAttribute($a)
        if ($v -and -not $resIds.ContainsKey($v)) {
            $missRef += ("{0}.{1} -> {2}" -f $n.GetAttribute("id"), $a, $v)
        } elseif ($v) {
            # 资源存在时顺便确认文件在
        }
    }
}

Write-Output ("resources = " + $resIds.Count)
if ($missFile.Count) { Write-Output "MISSING FILES:"; $missFile | ForEach-Object { Write-Output ("  " + $_) } } else { Write-Output "all resource files exist" }
if ($missRef.Count) { Write-Output "MISSING RESOURCE REFS:"; $missRef | ForEach-Object { Write-Output ("  " + $_) } } else { Write-Output "all src refs resolved" }

$unused = @()
foreach ($k in $resIds.Keys) {
    if (-not $doc.SelectSingleNode(("//image[@src='{0}' or @src-pressed='{0}' or @src-checked='{0}']" -f $k))) { $unused += $k }
}
if ($unused.Count) { Write-Output ("unused resources: " + ($unused -join ", ")) }
