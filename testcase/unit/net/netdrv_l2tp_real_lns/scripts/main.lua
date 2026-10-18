PROJECT = "netdrv_l2tp_real_lns"
VERSION = "1.0.0"

-- 真机长用例必须喂狗, 否则会被 WDT 重启 (见 testcase/AGENTS.md)
if wdt and wdt.init then
    wdt.init(9000)
    sys.taskInit(function()
        while true do
            sys.wait(1000)
            if wdt.feed then wdt.feed() end
        end
    end)
end

local cfg = require("lns_cfg")
local tests = require("l2tp_lns_test")

sys.taskInit(function()
    if not cfg.ready then
        log.warn("l2tp_real", "缺少 LNS 口令, 用例跳过:")
        log.warn("l2tp_real", "  PC  : $env:L2TP_PASS=\"...\" 后再跑")
        log.warn("l2tp_real", "  真机: 在 --script 目录里提供 lns_secret.txt (host/user/pass)")
    end
    testrunner = require("testrunner")
    testrunner.runBatch("netdrv_l2tp_real_lns", {
        { testTable = tests, testcase = "real_lns" },
    })
end)

sys.run()
