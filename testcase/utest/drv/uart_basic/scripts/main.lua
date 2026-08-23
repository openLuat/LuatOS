PROJECT = "uart_basic"
VERSION = "1.0.0"

local testrunner = require("testrunner")
local tests = require("uart_test")

sys.taskInit(function()
    testrunner.runBatch("uart_basic", {
        { testTable = tests.api_suite, testcase = "C层utest-uart_api(静态)" },
        { testTable = tests.dll_suite, testcase = "C层utest-uart_dll(导出符号)" },
    })
end)

sys.run()