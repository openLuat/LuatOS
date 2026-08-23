PROJECT = "netdrv_evt_pkg"
VERSION = "1.0.0"
testrunner = require("testrunner")
local tests = require("netdrv_evt_pkg_test")
sys.taskInit(function()
    testrunner.runBatch("netdrv_evt_pkg_suite", {
        { testTable = tests, testcase = "API surface" },
        { testTable = tests, testcase = "Error path" },
    })
end)
sys.run()
