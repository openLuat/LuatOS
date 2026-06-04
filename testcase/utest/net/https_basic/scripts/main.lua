PROJECT = "https_basic"
VERSION = "1.0.0"

AUTHOR = {"copilot"}

_G.sys = require("sys")
_G.sysplus = require("sysplus")

local testrunner = require("testrunner")
local tests = require("https_test")

sys.taskInit(function()
    testrunner.runBatch("https_basic", {
        { testTable = tests.https_suite, testcase = "C层utest-https外网连通性" }
    })
end)

sys.run()
