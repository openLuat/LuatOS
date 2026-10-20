-- netdrv DNS 客户端 (PC 模拟器) 接入测试入口
PROJECT = "netdrv_dns_pc"
VERSION = "1.0.0"

_G.sys = require("sys")

local testrunner = require("testrunner")
local tests = require("dns_pc_test")

-- 用 testrunner（与真机 dns_basic 同一套），它的 runBatch 在 task 里跑，
-- 用例内部的 sys.wait / sys.waitUntil 才能正常让出协程。
-- testsuite.runTestSuite 是同步执行模型, 网络类用例在那里 sys.wait 无法让出。
sys.taskInit(function()
    sys.wait(1500)   -- 等 PC 适配层发布 IP_READY
    testrunner.runBatch("netdrv_dns_pc", {
        { testTable = tests, testcase = "netdrv DNS 客户端 PC 接入" }
    })
end)

sys.run()
