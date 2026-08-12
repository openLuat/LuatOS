PROJECT = "netdrv_ipsec_basic"
VERSION = "1.0.0"

-- PC 模拟器联调真实 strongSwan 网关 ipsec.air32.cn (IKEv2 + EAP-MSCHAPv2)
-- 需要 scripts/ikev2-ca.crt (网关私建 CA), 由测试脚本作为 ipsec_ca_cert_pem 传入
-- 场景由环境变量 LUAT_IPSEC_TEST 选择:
--   connect : 正常拨号, 期望 IP_READY + 隧道 IP + DNS
--   badpass : 错误密码, 期望认证失败且不 ready
--   sanit   : 错误 SAN (自签/错名), 期望证书校验失败且不 ready
local mode = os.getenv and os.getenv("LUAT_IPSEC_TEST") or "connect"

testrunner = require("testrunner")
local tests = require("netdrv_ipsec_basic_test")
tests.mode = mode

sys.taskInit(function()
    testrunner.runBatch("netdrv_ipsec_basic_suite_" .. mode, {
        { testTable = tests, testcase = mode },
    })
end)
sys.run()
