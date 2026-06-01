PROJECT = "c_utest_dtls_basic"
VERSION = "1.0.0"

AUTHOR = {"copilot"}

_G.sys = require("sys")
_G.sysplus = require("sysplus")

local testrunner = require("testrunner")
local tests = require("c_utest_dtls_test")

sys.taskInit(function()
    testrunner.runBatch("c_utest_dtls_basic", {
        { testTable = tests.dtls_suite, testcase = "C层utest-dtls本地PSK回环" }
    })
end)

sys.run()
