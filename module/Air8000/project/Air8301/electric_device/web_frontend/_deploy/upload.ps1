param(
  [string]$App = 'luatos_electric_control',
  [string]$BaseDir = (Split-Path -Parent $PSScriptRoot),
  [string]$Root = '',            # 待上传目录（相对 BaseDir 或绝对路径），默认 BaseDir
  [string[]]$Only = @(),         # 只上传这些相对路径（相对 Root），默认全部
  [string]$McpUrl = 'https://api-iot.luatos.com/iot/mcp',
  [string]$TokenFile = "$env:USERPROFILE\.codebuddy\mcp.json"
)

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$cfg = Get-Content -Raw -Encoding UTF8 $TokenFile | ConvertFrom-Json
$token = $cfg.mcpServers.'api-iot.luatos.com'.headers.xkeyUserToken
if (-not $token) { throw 'xkeyUserToken not found' }

$script:session = $null
$script:id = 100

function Invoke-Mcp {
  param([string]$Body, [switch]$NoSession)
  $req = [Net.HttpWebRequest]::Create($McpUrl)
  $req.Method = 'POST'
  $req.ContentType = 'application/json'
  $req.Accept = 'application/json, text/event-stream'
  $req.Headers.Add('xkeyUserToken', $token)
  $req.Timeout = 180000
  if ($script:session -and -not $NoSession) { $req.Headers.Add('Mcp-Session-Id', $script:session) }
  $bytes = [Text.Encoding]::UTF8.GetBytes($Body)
  $req.ContentLength = $bytes.Length
  $s = $req.GetRequestStream(); $s.Write($bytes, 0, $bytes.Length); $s.Close()
  try {
    $resp = $req.GetResponse()
    if ($resp.Headers['Mcp-Session-Id']) { $script:session = $resp.Headers['Mcp-Session-Id'] }
    $sr = New-Object IO.StreamReader($resp.GetResponseStream())
    $text = $sr.ReadToEnd(); $sr.Close(); $resp.Close()
    return $text
  } catch {
    $e = $_.Exception
    $body = ''
    if ($e.Response) {
      try { $rs = New-Object IO.StreamReader($e.Response.GetResponseStream()); $body = $rs.ReadToEnd(); $rs.Close() } catch {}
    }
    return 'ERROR ' + $e.Message + ' | ' + $body
  }
}

$srcRoot = if ($Root) { $Root } else { $BaseDir }
if (-not [IO.Path]::IsPathRooted($srcRoot)) { $srcRoot = Join-Path $BaseDir $srcRoot }
$srcRoot = (Resolve-Path $srcRoot).Path
Write-Output ('--- 源目录: ' + $srcRoot)

# ---- Pre-flight check: all six pages must be bundled by _deploy/bundle.js ----
# Why: bundle.js --revert writes pages back to the "module references" form (every backup in
# _deploy/html-modules is in that form). If bundling is skipped afterwards, those pages have no
# assets/bundle reference and no window.__buildTime, so the sidebar footer can only show "--".
# (pages/topo.html and pages/settings.html were in exactly that state for a long time.)
# Upload is the last gate, so block here instead of shipping a half-built site.
# NOTE: keep this block ASCII-only -- PowerShell 5.1 reads BOM-less .ps1 as ANSI and non-ASCII
#       characters here have broken the script before.
$pageList = @('index.html', 'pages/devices.html', 'pages/alerts.html', 'pages/map.html', 'pages/topo.html', 'pages/settings.html')
$unpacked = @()
foreach ($pg in $pageList) {
  $fp = Join-Path $srcRoot $pg
  if (-not (Test-Path $fp)) { continue }
  $txt = Get-Content -Raw -Encoding UTF8 $fp
  if ($txt -notmatch 'assets/bundle/') { $unpacked += ($pg + ' [no bundle reference - still module form]') }
  elseif ($txt -notmatch 'window\.__buildTime=') { $unpacked += ($pg + ' [missing build-time injection]') }
}
if ($unpacked.Count -gt 0) {
  Write-Output 'X Pre-flight check FAILED - upload aborted, these pages are not bundled:'
  $unpacked | ForEach-Object { Write-Output ('   - ' + $_) }
  Write-Output '  fix: node _deploy/bundle.js --revert  ->  node _deploy/drop-tmap.js  ->  node _deploy/bundle.js'
  exit 1
}
Write-Output ('--- Pre-flight check OK: all ' + $pageList.Count + ' pages are bundled and build-stamped')

# 收集待上传文件（排除 _deploy 工具目录），按 relativePath 还原目录结构
$files = @()
Get-ChildItem -Recurse -File $srcRoot | Sort-Object FullName | ForEach-Object {
  $rel = $_.FullName.Substring($srcRoot.Length + 1) -replace '\\', '/'
  if ($rel -like '_deploy/*') { return }
  if ($Only.Count -and ($Only -notcontains $rel)) { return }
  $files += , @($rel, $_.FullName)
}

# 1) initialize
$script:id++
$init = @{
  jsonrpc = '2.0'; id = $script:id; method = 'initialize'
  params = @{
    protocolVersion = '2025-06-18'
    capabilities = @{}
    clientInfo = @{ name = 'luatos-deploy'; version = '1.2.0' }
  }
} | ConvertTo-Json -Depth 8 -Compress
Write-Output '--- initialize ---'
Write-Output (Invoke-Mcp -Body $init -NoSession)
Write-Output ('session=' + $script:session)

# 2) notifications/initialized
$notif = @{ jsonrpc = '2.0'; method = 'notifications/initialized'; params = @{} } | ConvertTo-Json -Depth 5 -Compress
Invoke-Mcp -Body $notif | Out-Null

Write-Output ('--- 待上传 ' + $files.Count + ' 个文件 ---')
$failed = @()
foreach ($f in $files) {
  $rel = $f[0]; $full = $f[1]
  $name = Split-Path $rel -Leaf
  $bytes = [IO.File]::ReadAllBytes($full)
  $b64 = [Convert]::ToBase64String($bytes)
  $script:id++
  $argsObj = @{ app = $App; fileName = $name; fileContent = $b64 }
  # relativePath 必须包含文件名（工具说明：“最后一段是文件名”）。
  # 根目录文件不传该参数（走「直接放在根目录、以 fileName 命名」的语义）。
  if ($rel -ne $name) { $argsObj.relativePath = $rel }
  $payload = @{
    jsonrpc = '2.0'; id = $script:id; method = 'tools/call'
    params = @{ name = 'uploadAppFile'; arguments = $argsObj }
  } | ConvertTo-Json -Depth 8 -Compress
  $res = Invoke-Mcp -Body $payload
  # 返回体是「JSON 套 JSON」，内层引号被转义成 \"code\":0
  $ok = ($res -match '\\"code\\":0')
  if (-not $ok) { $failed += $rel }
  Write-Output (('--- upload ' + $rel).PadRight(54) + $bytes.Length.ToString().PadLeft(8) + ' bytes  ' + $(if ($ok) { 'OK' } else { 'FAIL' }))
  if (-not $ok) { Write-Output $res }
}
if ($failed.Count) { Write-Output ('!!! 失败文件: ' + ($failed -join ', ')) } else { Write-Output '全部上传成功' }
