-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "appstore_test"
VERSION = "1.0.0"

-- 引入必须的库 (顺序: exwin 必须在 exapp 之前加载, 因为 exapp 的 UI 沙箱依赖 exwin)
-- exwin.lua 定义的是 local exwin = {}, 需要手动设为全局变量供 exapp.lua 使用
exwin = require("exwin")
local exapp_ok, exapp_err = pcall(require, "exapp")
if not exapp_ok then
    log.error("main", "exapp 加载失败, 请确保命令行包含 script/libs/ 路径", exapp_err)
end

-- 引入测试套件和测试运行器模块
testrunner = require("testrunner")

-- 载入需要测试的模块
appstore_test = require("appstore_test")

-- 开启一个task,运行测试
sys.taskInit(function()
    -- 初始化 AirUI (exapp 的 get_device_info 依赖 airui)
    -- 使用 480x320 分辨率
    local scr_w, scr_h = 480, 320
    if airui and airui.init then
        log.info("main", "初始化 AirUI " .. scr_w .. "x" .. scr_h)
        airui.init(scr_w, scr_h)
    else
        log.warn("main", "airui 模块不可用, 跳过 AirUI 初始化")
    end

    testrunner.runBatch("appstore_lifecycle", {
        {testTable = appstore_test, testcase = "应用商店全生命周期测试"}
    })
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
