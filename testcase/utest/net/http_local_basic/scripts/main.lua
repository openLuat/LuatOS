PROJECT = "http_local_basic"
VERSION = "1.0.0"

AUTHOR = {"luatos"}

_G.sys = require("sys")
_G.sysplus = require("sysplus")

local testrunner = require("testrunner")
local tests = require("http_local_test")

sys.taskInit(function()
    testrunner.runBatch("http_local_basic", {
        { testTable = tests.http_local_suite, testcase = "本地HTTP高强度测试" }
    })
end)

sys.run()
