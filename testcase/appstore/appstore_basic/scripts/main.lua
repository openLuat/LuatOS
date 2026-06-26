-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "appstore_test"
VERSION = "1.0.0"

-- 引入必须的库 (顺序: exwin 必须在 exapp 之前加载, 因为 exapp 的 UI 沙箱依赖 exwin)
-- exwin.lua 定义的是 local exwin = {}, 需要手动设为全局变量供 exapp.lua 使用
exwin = require("exwin")
local exapp_ok, exapp_err = pcall(require, "exapp")
if not exapp_ok then
    log.error("main", "exapp 加载失败", exapp_err)
    os.exit(1)  -- 快速失败, 避免后续 require 二次崩溃导致 NORESULT
end

-- 引入测试套件和测试运行器模块
testrunner = require("testrunner")

-- 载入需要测试的模块
appstore_test = require("appstore_test")

-- 开启一个task,运行测试
sys.taskInit(function()
    -- 检查是否为单App模式 (外部编排器通过 /testresult/single_app.json 传入)
    local single_cfg = io.readFile("/testresult/single_app.json")
    if single_cfg then
        log.info("main", "检测到 /testresult/single_app.json, 进入单App测试模式")
        appstore_test.test_single_app()
        -- test_single_app 内部会调用 os.exit(), 不会返回
        return
    end

    -- 批量模式: 初始化 LCD → AirUI (exapp 的 get_device_info 依赖 airui)
    -- 使用 480x854 竖屏分辨率
    local scr_w, scr_h = 480, 854

    -- PC模拟器: 必须先 lcd.init 初始化虚拟显示(SDL2窗口+帧缓冲), 再初始化 AirUI
    -- 否则 AirUI 渲染目标为空, 导致 ACCESS_VIOLATION 崩溃
    -- 参考 app_engine/factory/drv/lcd/lcd_common.lua 的 PC 分支处理
    if rtos and rtos.bsp and rtos.bsp() == "PC" then
        log.info("main", "PC模拟器: 初始化 LCD " .. scr_w .. "x" .. scr_h)
        lcd.init("custom", {w = scr_w, h = scr_h})
    else
        -- 真机: lcd 已由底层固件初始化, 只需 AirUI
        if lcd and lcd.init then
            log.info("main", "真机: 初始化 LCD " .. scr_w .. "x" .. scr_h)
            lcd.init(scr_w, scr_h)
        end
    end

    if airui and airui.init then
        log.info("main", "初始化 AirUI " .. scr_w .. "x" .. scr_h)
        airui.init(scr_w, scr_h)
        -- factory 在 airui_init 里设置 density_scale/screen_w/h, 测试环境手动设置
        _G.screen_w = scr_w
        _G.screen_h = scr_h
        _G.density_scale = 1.0
    else
        log.warn("main", "airui 模块不可用, 跳过 AirUI 初始化")
    end

    -- 在沙箱外一次性初始化 hzfont (PC内嵌字体, 无需路径), 避免沙箱重复 init/deinit 导致堆损坏
    if hzfont and hzfont.init then
        log.info("main", "初始化 hzfont (全局共享)")
        hzfont.init()
    end

    testrunner.runBatch("appstore_lifecycle", {
        {testTable = appstore_test, testcase = "应用商店全生命周期测试"}
    })
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
