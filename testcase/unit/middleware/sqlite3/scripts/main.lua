PROJECT = "sqlite3test"
VERSION = "1.0.0"

AUTHOR = {"copilot"}

testrunner = require("testrunner")

local sqlite3_tests = require("sqlite3_test")

sys.taskInit(function()
    testrunner.runBatch("sqlite3_suite", {
        { testTable = sqlite3_tests, testcase = "sqlite3综合测试" }
    })
end)

sys.run()
