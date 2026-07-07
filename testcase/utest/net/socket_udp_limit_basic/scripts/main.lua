PROJECT = "socket_udp_limit_basic"
VERSION = "1.0.0"

AUTHOR = {"copilot"}

_G.sys = require("sys")
_G.sysplus = require("sysplus")

local testrunner = require("testrunner")
local tests = require("udp_limit_test")

sys.taskInit(function()
    testrunner.runBatch("socket_udp_limit_basic", {
        { testTable = tests.udp_limit_suite, testcase = "PC UDP limit read drops tail" }
    })
end)

sys.run()
