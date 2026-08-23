PROJECT = "mobile_rfa_station1_replay"
VERSION = "1.0.0"
local testrunner = require("testrunner")
local tests = require("station1_replay")
sys.taskInit(function()
    testrunner.runBatch("mobile_rfa_station1_replay", {
        { testTable = tests.suite, testcase = "Station1 AT 流程 1:1 回放" },
    })
end)
sys.run()
