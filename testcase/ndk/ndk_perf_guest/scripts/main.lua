-- main.lua
-- NDK guest-implementation perf test entry point.
--
-- Runs the ndk_perf_guest tests (FNV-1a, CRC32 in commit 2; MD5, Base64,
-- heapsort added in commits 3-4). The framework feeds any PERF|... log
-- lines through to whatever captures stdout on PC, or to the UART log
-- on air1601.

PROJECT = "ndk_perf_guest"
VERSION = "1.0.0"

local testrunner = require("testrunner")
local ndk_perf_tests = require("ndk_perf_guest_test")

sys.taskInit(function()
    -- On air1601 we cannot afford long-running tests due to the watchdog;
    -- the commit 2 baseline already runs in < 1s on PC, so we keep the
    -- default behavior identical. The PERF_BENCHMARK env hook is a
    -- forward-compat slot for the larger profile set.
    local cases = {
        { testTable = ndk_perf_tests, testcase = "ndk guest-implementation perf" },
    }
    testrunner.runBatch("ndk_perf_guest", cases)
end)

sys.run()
