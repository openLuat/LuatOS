PROJECT = "airlink_uart_arq_hw"
VERSION = "1.0.0"
-- This suite exercises a UART peer and requires no Internet connection.
local netready = require("netready")
netready.exec = function() end
netready.deinit = function() end
local runner = require("testrunner")
if wdt and wdt.init then
    wdt.init(9000)
    sys.taskInit(function() while true do sys.wait(1000); wdt.feed() end end)
end
sys.taskInit(function()
    runner.runBatch("airlink_uart_arq_hw", {
        {testTable=require("arq_hw_test"), testcase="uart2_roundtrip"}
    })
end)
sys.run()
