-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "audio_play_pc"
VERSION = "1.0.0"

AUTHOR = {"copilot"}

testrunner = require("testrunner")

audio_play_pc_test = require("audio_play_pc_test")

sys.taskInit(function()
    testrunner.runBatch("audio_play_pc", {
        {testTable = audio_play_pc_test, testcase = "PC模拟器audio.play测试"}
    })
end)

sys.run()
