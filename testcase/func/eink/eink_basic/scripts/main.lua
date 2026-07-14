PROJECT = "eink_basic"
VERSION = "1.0.0"

AUTHOR = {"copilot"}

sys = require("sys")
local testrunner = require("testrunner")
local eink_tests = require("eink_test")

sys.taskInit(function()
    testrunner.runBatch("eink_basic", {
        {testTable = eink_tests, testcase = "eink 2.13 padded width smoke"}
    })
end)

sys.run()
