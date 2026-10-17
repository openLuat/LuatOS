# L2TP mock LNS 场景全量回归 (PC 模拟器)
# 用法: pwsh -File tools/l2tp_matrix.ps1   (工作目录 = 仓库根)
$exe = ".\bsp\pc\build\out\luatos-lua.exe"
$cases = @(
  @{name="pap";          args="--port 1701 --auth pap";},
  @{name="chap";         args="--port 1702 --auth chap";},
  @{name="reject";       args="--port 1703 --reject-auth";},
  @{name="reconnect";    args="--port 1701 --drop-after 8";},
  @{name="mschapv2";     args="--port 1704 --auth mschapv2";},
  @{name="mschapv2-bad"; args="--port 1705 --auth mschapv2 --bad-auth-response";},
  @{name="secret";       args="--port 1706 --auth pap --secret tunnel-secret-123";},
  @{name="secret-bad";   args="--port 1707 --auth pap --secret tunnel-secret-123";},
  @{name="no-dns";       args="--port 1708 --auth pap --no-dns";}
)
$fail = 0
foreach ($c in $cases) {
  $mock = Start-Process -FilePath "python" `
      -ArgumentList "testcase/unit/net/netdrv_l2tp_basic/mock_lns.py $($c.args)" `
      -PassThru -WindowStyle Hidden
  Start-Sleep -Seconds 2
  $env:LUAT_L2TP_TEST = $c.name
  $out = & $exe testcase\common\scripts\ testcase\unit\net\netdrv_l2tp_basic\scripts\ 2>&1
  $verdict = if ($out | Select-String -Pattern "### OVERALL_PASS") { "PASS" }
             elseif ($out | Select-String -Pattern "### OVERALL_FAIL") { "FAIL" } else { "??" }
  $total = (($out | Select-String -Pattern "Total:\s*(\d+) passed, (\d+) failed") |
            Select-Object -Last 1).Matches.Groups[1..2].Value -join "/"
  if ($verdict -ne "PASS") { $fail++ }
  echo ("{0,-14} {1}  passed/failed={2}" -f $c.name, $verdict, $total)
  Stop-Process -Id $mock.Id -Force -ErrorAction SilentlyContinue
  Start-Sleep -Seconds 1
}
echo "=== matrix done, failures=$fail ==="
