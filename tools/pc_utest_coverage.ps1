param(
    [string]$WorktreeRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path,
    [string]$TestcaseScripts = "..\..\testcase\unit_testcase_tools\c_utest_crypto_basic\scripts\",
    [switch]$SkipBuild
)

$ErrorActionPreference = "Stop"

$pcDir = Join-Path $WorktreeRoot "bsp\pc"
$exePath = Join-Path $pcDir "build\out\luatos-lua.exe"
$commonScripts = "..\..\testcase\common\scripts"
$coverageDir = Join-Path $WorktreeRoot "build\coverage\pc_utest_crypto_basic"
$htmlDir = Join-Path $coverageDir "html"

New-Item -ItemType Directory -Path $coverageDir -Force | Out-Null
$env:LUAT_USE_UTEST = "y"

if (-not $SkipBuild) {
    Push-Location $pcDir
    try {
        cmd /c build_windows_32bit_msvc.bat
    }
    finally {
        Pop-Location
    }
}

if (-not (Test-Path $exePath)) {
    throw "PC simulator binary not found: $exePath"
}
if (-not (Test-Path (Join-Path $pcDir $commonScripts))) {
    throw "Common testcase scripts not found: $(Join-Path $pcDir $commonScripts)"
}

$testcaseScriptsPath = if ([System.IO.Path]::IsPathRooted($TestcaseScripts)) {
    $TestcaseScripts.TrimEnd('\')
} else {
    $TestcaseScripts.TrimEnd('\')
}
if (-not (Test-Path (Join-Path $pcDir $testcaseScriptsPath))) {
    throw "Target testcase scripts not found: $testcaseScriptsPath"
}

$occCandidates = @(
    (Get-Command OpenCppCoverage -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -ErrorAction SilentlyContinue),
    (Get-Command OpenCppCoverage.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -ErrorAction SilentlyContinue),
    $(if ($env:ProgramW6432) { Join-Path $env:ProgramW6432 "OpenCppCoverage\OpenCppCoverage.exe" } else { $null }),
    $(if ($env:ProgramFiles) { Join-Path $env:ProgramFiles "OpenCppCoverage\OpenCppCoverage.exe" } else { $null }),
    $(if ($env:ProgramFiles -and $env:ProgramFiles -ne "C:\Program Files") { Join-Path "C:\Program Files" "OpenCppCoverage\OpenCppCoverage.exe" } else { $null }),
    $(if (${env:ProgramFiles(x86)}) { Join-Path ${env:ProgramFiles(x86)} "OpenCppCoverage\OpenCppCoverage.exe" } else { $null }),
    "C:\Program Files\OpenCppCoverage\OpenCppCoverage.exe"
) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique

if (-not $occCandidates -or $occCandidates.Count -eq 0) {
    Write-Host "[coverage] OpenCppCoverage not found. Install it first, then rerun:"
    Write-Host "[coverage]   OpenCppCoverage --export_type=html:`"$htmlDir`" --sources=`"$WorktreeRoot\components`" --sources=`"$WorktreeRoot\luat`" -- `"$exePath`" $commonScripts $TestcaseScripts"
    exit 0
}
$occExe = if ($occCandidates -is [System.Array]) { $occCandidates[0] } else { $occCandidates }

$coverageCmd = @(
    "--export_type=html:$htmlDir"
    "--sources=$WorktreeRoot\components"
    "--sources=$WorktreeRoot\luat"
    "--working_dir=$pcDir"
    "--"
    "$exePath"
    "$commonScripts"
    "$testcaseScriptsPath"
)

Push-Location $pcDir
try {
    & $occExe @coverageCmd
}
finally {
    Pop-Location
}

Write-Host "[coverage] HTML report generated: $htmlDir\index.html"
