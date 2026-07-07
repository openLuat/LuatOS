PROJECT = "spi_msgs_ch347_flash"
VERSION = "1.0.0"

require("flash_test")

-- sys.taskInit(function()
--     testrunner.runBatch("spi_msgs_ch347_flash", {
--         { testTable = spi_msgs_ch347_flash_test, testcase = "PC sim: CH347 USB-SPI + 真实 NOR flash 走 trans_msgs/xfer2 路径" }
--     })
-- end)

sys.run()
