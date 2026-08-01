PROJECT = "spi_soft_basic"
VERSION = "1.0.0"

local testrunner = require("testrunner")
local tests = require("spi_soft_test")

sys.taskInit(function()
    testrunner.runBatch("spi_soft_basic", {
        { testTable = tests.xfer_suite, testcase = "软SPI全双工xfer-4种模式" },
        { testTable = tests.multibyte_suite, testcase = "软SPI多字节xfer" },
        { testTable = tests.send_suite, testcase = "软SPI发送" },
        { testTable = tests.recv_suite, testcase = "软SPI接收" },
    })
end)

sys.run()
