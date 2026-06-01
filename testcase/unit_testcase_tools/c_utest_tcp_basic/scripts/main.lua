PROJECT = "c_utest_tcp_basic"
VERSION = "1.0.0"

AUTHOR = {"copilot"}

_G.sys = require("sys")
_G.sysplus = require("sysplus")

local testrunner = require("testrunner")
local tests = require("c_utest_tcp_test")

sys.taskInit(function()
    testrunner.runBatch("c_utest_tcp_basic", {
        { testTable = tests.tcp_suite, testcase = "C层utest-tcp外网连通性" }
    })
end)

sys.run()
