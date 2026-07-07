-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "audio_play_pc"
VERSION = "1.0.0"

AUTHOR = {"copilot"}

testrunner = require("testrunner")

audio_play_pc_test = require("audio_play_pc_test")
audio_v2_pc_test = require("audio_v2_pc_test")

sys.taskInit(function()
    local batches = {}
    if os.getenv("LUAT_AUDIO_V2_EXPECT_NO_DEVICE") ~= "1" then
        table.insert(batches, {testTable = audio_play_pc_test, testcase = "PC模拟器audio.play测试"})
    end
    table.insert(batches, {testTable = audio_v2_pc_test, testcase = "PC模拟器audio_v2全双工测试"})
    testrunner.runBatch("audio_play_pc", batches)
end)

sys.run()
