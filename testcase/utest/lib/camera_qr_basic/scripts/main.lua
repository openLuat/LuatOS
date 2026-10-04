PROJECT = "camera_qr_basic"
VERSION = "1.0.0"

AUTHOR = {"copilot"}

local testrunner = require("testrunner")
local tests = require("camera_qr_test")

sys.taskInit(function()
    testrunner.runBatch("camera_qr_basic", {
        { testTable = tests.decode_suite, testcase = "camera.utest_qr_decode(图片解码)" }
    })
end)

sys.run()
