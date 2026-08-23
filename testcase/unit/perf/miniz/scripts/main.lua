-- LuaTools requires PROJECT and VERSION information
PROJECT = "miniztest"
VERSION = "1.0.0"

-- Author list helps trace ownership
AUTHOR = {"qa", "copilot"}

-- Test harness modules
sys = require("sys")
testrunner = require("testrunner")

-- Load test suite
miniz_test = require("miniz_test")

-- Kick off the batch
sys.taskInit(function()
    testrunner.runBatch("miniz", {
        { testTable = miniz_test, testcase = "miniz inflate" }
    })
end)

-- User code end
sys.run()
-- Do not add any statements after sys.run()
