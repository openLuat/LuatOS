PROJECT = "pgfs_regression_basic"
VERSION = "1.0.0"

testrunner = require("testrunner")
pgfs_tests = require("pgfs_regression_test")

sys.taskInit(function()
    testrunner.runBatch("pgfs_regression_basic", {
        {testTable = pgfs_tests, testcase = "pgfs回归"}
    })
end)
sys.run()
