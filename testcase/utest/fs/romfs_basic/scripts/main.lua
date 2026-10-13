-- romfs_basic main.lua
PROJECT = "romfs_basic"
VERSION = "1.0.0"

local testrunner = require("testrunner")
local romfs_test = require("romfs_test")

sys.taskInit(function()
    testrunner.runBatch("romfs_basic", {
        {testTable = romfs_test, testcase = "romfs 只读文件系统(指针+回调双模式)"}
    })
end)
sys.run()
