PROJECT = "vfs_lfs2_ops_test"
VERSION = "1.0.0"

sys = require("sys")
testrunner = require("testrunner")

vfs_lfs2_ops_test = require("vfs_lfs2_ops_test")

sys.taskInit(function()
    testrunner.runBatch("vfs_lfs2_ops", {
        {testTable = vfs_lfs2_ops_test, testcase = "VFS lfs2函数指针表验证"}
    })
end)

sys.run()
