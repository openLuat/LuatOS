PROJECT = "fatfs_multi_mount"
VERSION = "1.0.0"

sys = require("sys")
testrunner = require("testrunner")

local fatfs_multi_test = require("fatfs_multi_test")

sys.taskInit(function()
    testrunner.runBatch("fatfs_multi_mount", {
        { testTable = fatfs_multi_test, testcase = "fatfs multi volume mount" }
    })
end)

sys.run()
