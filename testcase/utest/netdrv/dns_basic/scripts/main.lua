PROJECT = "dns_basic"
VERSION = "1.0.0"

AUTHOR = {"mavis"}

_G.sys = require("sys")
_G.sysplus = require("sysplus")

local testrunner = require("testrunner")
local tests = require("dns_test")

sys.taskInit(function()
    testrunner.runBatch("dns_basic", {
        { testTable = tests.dns_suite, testcase = "DNS utest 全量" },
        { testTable = tests.dns_suite, testcase = "DNS 报文编码与域名校验" },
        { testTable = tests.dns_suite, testcase = "DNS A/AAAA 应答解析" },
        { testTable = tests.dns_suite, testcase = "DNS 并发在途与双栈合并" },
        { testTable = tests.dns_suite, testcase = "DNS 缓存命中/TTL/LRU" },
        { testTable = tests.dns_suite, testcase = "DNS 负缓存与 SERVFAIL" },
        { testTable = tests.dns_suite, testcase = "DNS 重试退避与服务器轮转" },
        { testTable = tests.dns_suite, testcase = "DNS 在途上限与节奏限速" },
        { testTable = tests.dns_suite, testcase = "DNS 畸形报文拒绝" },
        { testTable = tests.dns_suite, testcase = "DNS 缓存失效与等待者合并" },
        { testTable = tests.dns_suite, testcase = "DNS 发送失败与释放回收" },
        { testTable = tests.dns_suite, testcase = "DNS 内存泄漏检查" },
    })
end)

sys.run()
