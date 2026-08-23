-- netdrv LWIP 层拦截 + send_raw 注回应答 闭环测试 (PC 模拟器, whale 设备)
PROJECT = "netdrv_lwip_intercept_basic"
VERSION = "1.0.0"

local testsuite = require("testsuite")
local tests = require("netdrv_lwip_intercept_test")

sys.taskInit(function()
    local ok = testsuite.runTestSuite({}, tests)
    if rtos.bsp() == "PC" then
        os.exit(ok and 0 or 1)
    end
end)

sys.run()
