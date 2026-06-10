PROJECT = "pgfs_basic"
VERSION = "1.0.0"

testrunner = require("testrunner")
pgfs_tests = require("pgfs_test")

sys.taskInit(function()
    testrunner.runBatch("pgfs_basic", {
        {testTable = pgfs_tests, testcase = "pgfs代际回退"}
    })
end)
sys.run()
