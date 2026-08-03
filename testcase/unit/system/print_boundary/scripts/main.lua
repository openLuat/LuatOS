PROJECT = "print_boundary_test"
VERSION = "1.0.0"

sys = require("sys")
testrunner = require("testrunner")

print_boundary_test = require("print_boundary_test")

sys.taskInit(function()
    testrunner.runBatch("print_boundary", {
        {testTable = print_boundary_test, testcase = "print缓冲区边界测试"}
    })
end)

sys.run()
