PROJECT = "gb28181test"
VERSION = "0.1.0"

-- 修改者的名称, 方便日后维护
AUTHOR = {"luatos"}

local testrunner = require("testrunner")
local gb28181_tests = require("gb28181_test")

sys.taskInit(function()
    testrunner.runBatch("gb28181_lua", {
        {testTable = gb28181_tests, testcase = "GB28181设备侧Lua层"}
    })
end)

sys.run()
