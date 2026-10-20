PROJECT = "socket_local_port_basic"
VERSION = "1.0.0"

_G.sys = require("sys")

local testrunner = require("testrunner")
local tests = require("local_port_test")

sys.taskInit(function()
    testrunner.runBatch("socket_local_port_basic", {
        { testTable = tests.local_port_suite, testcase = "socket.localPort" }
    })
end)

sys.run()
