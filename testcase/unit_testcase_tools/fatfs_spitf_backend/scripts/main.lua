PROJECT = "fatfs_spitf_backend"
VERSION = "1.0.0"

sys = require("sys")
testrunner = require("testrunner")

local spitf_test = require("spitf_test")

sys.taskInit(function()
    testrunner.runBatch("fatfs_spitf_backend", {
        { testTable = spitf_test, testcase = "fatfs SPI TF backend" }
    })
end)

sys.run()
