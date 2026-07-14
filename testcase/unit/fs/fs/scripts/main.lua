PROJECT = "fs_test"
VERSION = "1.0.0"

sys = require("sys")
testrunner = require("testrunner")

fs_test = require("fs_test")

sys.taskInit(function()
    testrunner.runBatch("fs", {
        {testTable = fs_test, testcase = "fs测试"}
    })
end)

sys.run()