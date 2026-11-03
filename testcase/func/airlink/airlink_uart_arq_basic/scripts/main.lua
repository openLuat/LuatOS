PROJECT = "airlink_uart_arq_basic"
VERSION = "1.0.0"
local netready = require("netready")
netready.exec = function() end
netready.deinit = function() end
local runner = require("testrunner")
sys.taskInit(function()
    runner.runBatch(PROJECT, {{testTable=require("arq_test"), testcase="arq_state_machine"}})
end)
sys.run()
