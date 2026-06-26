PROJECT = "tfs_basic"
VERSION = "1.0.0"

local testrunner = require("testrunner")
local tfs_tests = require("tfs_test")

sys.taskInit(function()
    testrunner.runBatch("tfs_basic", {
        {testTable = tfs_tests, testcase = "TFS checkpoint/powercut basic"}
    })
end)
sys.run()