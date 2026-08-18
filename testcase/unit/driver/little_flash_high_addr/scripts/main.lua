PROJECT = "little_flash_high_addr"
VERSION = "1.0.0"

sys = require("sys")
testrunner = require("testrunner")
little_flash_high_addr_test = require("little_flash_high_addr_test")

sys.taskInit(function()
    testrunner.runBatch("little_flash_high_addr", {
        { testTable = little_flash_high_addr_test, testcase = "lf high address access > 16 MB" }
    })
end)

sys.run()
