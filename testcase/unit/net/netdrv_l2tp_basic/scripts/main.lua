PROJECT = "netdrv_l2tp_basic"
VERSION = "1.0.0"

-- 通过环境变量 LUAT_L2TP_TEST 选择场景 (默认 pap):
--   pap       : PAP 认证 + 隧道内 TCP echo   (mock LNS 端口 1701)
--   chap      : CHAP-MD5 认证 + TCP echo      (mock LNS 端口 1702)
--   reject    : 密码错误, 认证失败, 不 ready   (mock LNS 端口 1703)
--   reconnect : 会话中途断开后自动重连成功      (mock LNS 端口 1701, --drop-after)
local mode = os.getenv and os.getenv("LUAT_L2TP_TEST") or "pap"
local port = 1701
if mode == "chap" then
    port = 1702
elseif mode == "reject" then
    port = 1703
end

testrunner = require("testrunner")
local tests = require("netdrv_l2tp_basic_test")
tests.mode = mode
tests.port = port

sys.taskInit(function()
    testrunner.runBatch("netdrv_l2tp_basic_suite_" .. mode, {
        { testTable = tests, testcase = mode },
    })
end)
sys.run()
