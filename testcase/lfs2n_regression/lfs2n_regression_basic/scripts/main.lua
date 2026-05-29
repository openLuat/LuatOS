PROJECT = "lfs2n_regression"
VERSION = "1.1.0"

sys = require("sys")
testrunner = require("testrunner")
lfs2n_regression_test = require("lfs2n_regression_test")

sys.taskInit(function()
    testrunner.runBatch("lfs2n_regression", {
        {testTable = lfs2n_regression_test, testcase = "lfs2 nand regression"}
    })
end)

sys.run()
