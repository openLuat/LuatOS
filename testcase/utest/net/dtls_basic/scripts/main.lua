PROJECT = "dtls_basic"
VERSION = "1.0.1"

AUTHOR = {"copilot"}

_G.sys = require("sys")
_G.sysplus = require("sysplus")

local testrunner = require("testrunner")
local tests = require("dtls_test")

sys.taskInit(function()
    testrunner.runBatch("dtls_basic", {
        { testTable = tests.dtls_suite, testcase = "C层utest-dtls本地PSK回环" },
        { testTable = tests.dtls_suite, testcase = "C层utest-dtls CA证书回环" },
        { testTable = tests.dtls_suite, testcase = "C层utest-dtls CA不匹配被拒" },
        { testTable = tests.dtls_suite, testcase = "C层utest-dtls mTLS双向认证" },
        { testTable = tests.dtls_suite, testcase = "C层utest-dtls 证书解析边界" },
    })
end)

sys.run()
