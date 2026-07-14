PROJECT = "ndk_basic"
VERSION = "1.0.0"
AUTHOR = {"copilot"}

local testrunner = require("testrunner")
local ndk_lifecycle = require("ndk_lifecycle_test")
local ndk_fp_isa = require("ndk_fp_isa_test")
local ndk_fp_arith = require("ndk_fp_arith_test")
local ndk_fp_rounding = require("ndk_fp_rounding_test")
local ndk_fp_trap = require("ndk_fp_trap_test")

sys.taskInit(function()
    testrunner.runBatch("ndk_basic", {
        { testTable = ndk_lifecycle, testcase = "ndk lifecycle tests" },
        { testTable = ndk_fp_isa, testcase = "ndk FP ISA selection tests" },
        { testTable = ndk_fp_arith, testcase = "ndk FP arithmetic tests" },
        { testTable = ndk_fp_rounding, testcase = "ndk FP rounding/convert tests" },
        { testTable = ndk_fp_trap, testcase = "ndk FP trap tests" },
    })
end)

sys.run()
