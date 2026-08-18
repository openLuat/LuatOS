PROJECT = "https_local_basic"
VERSION = "1.0.0"

AUTHOR = {"luatos"}

_G.sys = require("sys")
_G.sysplus = require("sysplus")

local testrunner = require("testrunner")
local tests = require("https_local_test")

sys.taskInit(function()
    testrunner.runBatch("https_local_basic", {
        { testTable = tests.https_local_suite, testcase = "本地HTTPS高强度测试" }
    })
end)

sys.run()
