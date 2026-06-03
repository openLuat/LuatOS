PROJECT = "ndk_hostabi_basic"
VERSION = "1.0.0"
AUTHOR = {"copilot"}

local testrunner = require("testrunner")
local meta_tests = require("ndk_hostabi_meta_test")
local event_tests = require("ndk_hostabi_event_test")
local gpio_tests = require("ndk_hostabi_gpio_test")
local uart_tests = require("ndk_hostabi_uart_test")
local crypto_tests = require("ndk_hostabi_crypto_test")
local rvc_tests = require("ndk_hostabi_rvc_test")
local crypto_perf_tests = require("ndk_crypto_perf_test")

sys.taskInit(function()
    local cases = {}
    if os.getenv("NDK_ONLY_CRYPTO_PERF") == "1" then
        table.insert(cases, { testTable = crypto_perf_tests, testcase = "ndk crypto perf benchmark" })
    else
        table.insert(cases, { testTable = meta_tests, testcase = "ndk hostabi meta tests" })
        table.insert(cases, { testTable = event_tests, testcase = "ndk hostabi event tests" })
        table.insert(cases, { testTable = gpio_tests, testcase = "ndk hostabi GPIO tests" })
        table.insert(cases, { testTable = uart_tests, testcase = "ndk hostabi UART tests" })
        table.insert(cases, { testTable = crypto_tests, testcase = "ndk hostabi CRYPTO tests" })
        table.insert(cases, { testTable = rvc_tests, testcase = "ndk hostabi RV32C tests" })
        if os.getenv("NDK_ENABLE_CRYPTO_PERF") == "1" then
            table.insert(cases, { testTable = crypto_perf_tests, testcase = "ndk crypto perf benchmark" })
        end
    end
    testrunner.runBatch("ndk_hostabi", cases)
end)

sys.run()
