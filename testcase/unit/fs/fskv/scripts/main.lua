PROJECT = "fskvtest"
VERSION = "1.0.0"

-- Author for maintenance
AUTHOR = {"copilot"}

-- Load test suite and runner
testrunner = require("testrunner")

-- Load the test cases
fskv_tests = require("fskv_test")

sys.taskInit(function()
    testrunner.runBatch("fskv_demo", {
        {testTable = fskv_tests, testcase = "FSKV测试"}
    })
end)

-- End of user code ---------------------------------------------
sys.run()
-- Do not add any code after sys.run()
