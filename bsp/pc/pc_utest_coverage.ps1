param(
    [string]$WorktreeRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path,
    [string]$Suite,
    [string]$TestcaseScripts,
    [string]$CoverageDir,
    [switch]$SkipBuild
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($Suite) -and [string]::IsNullOrWhiteSpace($TestcaseScripts)) {
    throw "Specify -Suite <suite-name> or -TestcaseScripts <scripts-path>."
}
if (-not [string]::IsNullOrWhiteSpace($Suite) -and -not [string]::IsNullOrWhiteSpace($TestcaseScripts)) {
    throw "Use either -Suite or -TestcaseScripts, not both."
}

$pcDir = $PSScriptRoot
$exePath = Join-Path $pcDir "build\out\luatos-lua.exe"
$commonScripts = "..\..\testcase\common\scripts"

if (-not [string]::IsNullOrWhiteSpace($Suite)) {
    $suiteName = $Suite
    $testcaseScriptsPath = "..\..\testcase\unit_testcase_tools\$Suite\scripts"
}
else {
    $testcaseScriptsPath = $TestcaseScripts.TrimEnd('\')
    $resolvedScriptsDir = if ([System.IO.Path]::IsPathRooted($testcaseScriptsPath)) {
        $testcaseScriptsPath
    }
    else {
        Join-Path $pcDir $testcaseScriptsPath
    }
    if (-not (Test-Path $resolvedScriptsDir)) {
        throw "Target testcase scripts not found: $resolvedScriptsDir"
    }
    $suiteName = Split-Path (Split-Path $resolvedScriptsDir -Parent) -Leaf
}

$testcaseScriptsPath = $testcaseScriptsPath.TrimEnd('\')
$resolvedTestcaseDir = if ([System.IO.Path]::IsPathRooted($testcaseScriptsPath)) {
    $testcaseScriptsPath
}
else {
    Join-Path $pcDir $testcaseScriptsPath
}

if (-not (Test-Path $resolvedTestcaseDir)) {
    throw "Target testcase scripts not found: $resolvedTestcaseDir"
}

$coverageDir = if ([string]::IsNullOrWhiteSpace($CoverageDir)) {
    Join-Path $WorktreeRoot "build\coverage\$suiteName"
}
elseif ([System.IO.Path]::IsPathRooted($CoverageDir)) {
    $CoverageDir
}
else {
    Join-Path $WorktreeRoot $CoverageDir
}
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
    Write-Host "[coverage]   .\\pc_utest_coverage.ps1 -Suite $suiteName"
    exit 0
}
$occExe = if ($occCandidates -is [System.Array]) { $occCandidates[0] } else { $occCandidates }

$coverageCmd = @(
    "--export_type=html:$htmlDir"
    "--sources=$WorktreeRoot\components"
    "--sources=$WorktreeRoot\luat"
    "--sources=$WorktreeRoot\bsp\pc"
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

Write-Host "[coverage] Suite: $suiteName"
Write-Host "[coverage] HTML report generated: $htmlDir\index.html"
