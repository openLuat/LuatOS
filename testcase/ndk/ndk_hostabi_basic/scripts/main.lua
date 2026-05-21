-- main.lua
-- NDK host ABI basic test entry point

PROJECT = "ndk_hostabi_basic"
VERSION = "1.0.0"

local testrunner = require("testrunner")
local ndk_hostabi_tests = require("ndk_hostabi_test")
local ndk_crypto_perf_tests = require("ndk_crypto_perf_test")

sys.taskInit(function()
    local cases = {}
    if os.getenv("NDK_ONLY_CRYPTO_PERF") == "1" then
        table.insert(cases, { testTable = ndk_crypto_perf_tests, testcase = "ndk crypto perf benchmark" })
    else
        table.insert(cases, { testTable = ndk_hostabi_tests, testcase = "ndk host abi regression" })
        if os.getenv("NDK_ENABLE_CRYPTO_PERF") == "1" then
            table.insert(cases, { testTable = ndk_crypto_perf_tests, testcase = "ndk crypto perf benchmark" })
        end
    end
    testrunner.runBatch("ndk_hostabi", cases)
end)

sys.run()
