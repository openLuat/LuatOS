-- httpsrv 修复回归测试入口 (PC 模拟器, posix 后端)
-- 覆盖 2026-10 httpsrv 五项修复, 用例见 httpsrv_test.lua:
--   httpsrv.stop 后同端口重绑、静态文件带 query、svg MIME、
--   大包 POST、并发连接、连接中途断开(RST/EOF)后服务仍可用
-- 注: lwIP 后端跨 pbuf 请求体截断(#1)的对应路径已在 Air1601 真机验证,
--     本用例在 PC 后端跑同一大包 POST, 覆盖公共的 http.c 累积解析逻辑
PROJECT = "httpsrv_basic"
VERSION = "1.0.0"

_G.sys = require("sys")

local testrunner = require("testrunner")
local tests = require("httpsrv_test")

sys.taskInit(function()
    sys.wait(1500)   -- 等 PC 适配层发布 IP_READY (与 netdrv_dns_pc 相同套路)
    tests.setup()
    testrunner.runBatch("httpsrv_basic", {
        { testTable = tests, testcase = "httpsrv 修复回归" }
    })
    -- runBatch 在 PC 上会 os.exit; 真机落到这里时停掉服务器
    tests.teardown()
end)

sys.run()
