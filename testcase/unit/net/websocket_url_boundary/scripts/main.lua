PROJECT = "websocket_url_boundary_test"
VERSION = "1.0.0"

sys = require("sys")
testrunner = require("testrunner")

websocket_url_boundary_test = require("websocket_url_boundary_test")

sys.taskInit(function()
    testrunner.runBatch("websocket_url_boundary", {
        {testTable = websocket_url_boundary_test, testcase = "WebSocket URL解析边界测试"}
    })
end)

sys.run()
