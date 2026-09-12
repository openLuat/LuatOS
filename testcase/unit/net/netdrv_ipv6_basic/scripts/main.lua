-- netdrv.ipv6 基础功能测试 (PC 模拟器, whale 虚拟网卡)
PROJECT = "netdrv_ipv6_basic"
VERSION = "1.0.0"

local testsuite = require("testsuite")
local tests = require("netdrv_ipv6_test")

sys.taskInit(function()
    local ok = testsuite.runTestSuite({}, tests)
    if rtos.bsp() == "PC" then
        os.exit(ok and 0 or 1)
    end
end)

sys.run()
