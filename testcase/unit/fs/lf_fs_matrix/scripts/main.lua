PROJECT = "lf_fs_matrix"
VERSION = "1.0.0"

sys = require("sys")
testrunner = require("testrunner")
lf_fs_matrix_test = require("lf_fs_matrix_test")

sys.taskInit(function()
    testrunner.runBatch("lf_fs_matrix", {
        { testTable = lf_fs_matrix_test, testcase = "lf 3fs matrix" }
    })
end)

sys.run()
