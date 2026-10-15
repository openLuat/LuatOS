-- netdrv 现代 DNS 客户端 真机测试入口
PROJECT = "dns_basic"
VERSION = "1.0.0"

AUTHOR = {"mavis"}

--[[
本测试覆盖 netdrv 新 DNS 客户端的真机行为:
解析 / 缓存命中与过期 / LRU 淘汰 / 负缓存 / 并发在途 / 双栈合并 /
手动失效 / 运行时配置 / 长跑无内存增长.

依赖:
  1. 板子已联网(以太网或蜂窝均可), testrunner 会先调 netready 拉起网卡
  2. 固件里 LUAT_USE_NETDRV_DNS_CLIENT 宏已打开(默认开),
     即 netdrv.CTRL_DNS 这个常量必须存在
]]

_G.sys = require("sys")
_G.sysplus = require("sysplus")

local testrunner = require("testrunner")
local dnstest = require("dns_test")

-- DNS 解析要等真实网络应答, 慢网下整套可能跑几十秒, 必须喂狗
if wdt and wdt.init then
    wdt.init(9000)
    sys.taskInit(function()
        while true do
            sys.wait(1000)
            if wdt.feed then wdt.feed() end
        end
    end)
end

sys.taskInit(function()
    testrunner.runBatch("dns_basic", {
        { testTable = dnstest, testcase = "netdrv DNS 客户端真机测试" }
    })
end)

sys.run()
