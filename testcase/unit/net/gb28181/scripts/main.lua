PROJECT = "gb28181test"
VERSION = "0.3.0"

-- 修改者的名称, 方便日后维护
AUTHOR = {"luatos"}

local testrunner = require("testrunner")
local facade_tests = require("gb28181_test")         -- Lua 门面 exgb28181.lua
local c_tests      = require("gb28181_c_test")       -- C 绑定 gb28181.*
local client_tests = require("gb28181_client_test")  -- 信令客户端 exgb28181client.lua

sys.taskInit(function()
    testrunner.runBatch("gb28181", {
        {testTable = c_tests,      testcase = "GB28181-C绑定"},
        {testTable = client_tests, testcase = "GB28181-信令客户端"},
        {testTable = facade_tests, testcase = "GB28181-Lua门面"}
    })
end)

sys.run()
