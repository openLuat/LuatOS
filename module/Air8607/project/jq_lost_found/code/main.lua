--[[
@module  main
@summary 失物招领公示 - 入口（只做加载与启动编排）
@version 1.0.0
@date    2026.10.30
@board   Air8607（Air1603）+ 10 寸 RGB 1024x600 + GT911 电容触摸

=== 功能 ===
1. 公示列表：拾得 / 遗失两类条目，卡片显示名称、时间、地点、联系方式、状态。
2. 搜索：按物品名称关键词、时间（今天/近7天）、类型（拾得/遗失）组合筛选。
3. 新增：类型 + 物品名称 + 时间 + 地点 + 联系方式（软键盘 + 拼音候选输入中文）。
4. 认领：遗失物品必须凭身份证领取（18 位身份证校验位核对），拾得物品标记处理完成。
5. 顶栏实时统计公示中 / 已认领条数，时钟每秒刷新。

=== 启动顺序（有依赖，勿调整）===
1 power_on     供电 / 背光 PWM 归零
2 exd.setup    RGB 时序 + 帧缓冲
3 airui.init   分辨率 + 中文字库
4 store.init   业务数据先就绪
5 ui_main.build 主界面
6 预构建浮层   表单 / 领取 / 输入 / 提示（固定 z 序，键盘最后）
7 touch_init   触摸绑定
8 backlight_on 首帧后点亮背光
9 每秒 tick    时钟刷新
]]

PROJECT = "lost_found"
VERSION = "1.0.0"

local conf = require "conf"
local store = require "store"
local ui_main = require "ui_main"
local ui_form = require "ui_form"
local ui_claim = require "ui_claim"
local ui_input = require "ui_input"
local ui_alert = require "ui_alert"
local exd = require "exd_air8607_rgb"

local SW, SH = conf.W, conf.H

local function is_pc()
    local ok, bsp = pcall(function() return rtos.bsp() end)
    return ok and bsp == "PC"
end

-- 供电与引脚：背光 PWM 先给 0 占空比（黑屏），UI 搭好再点亮
local function power_on()
    pwm.setup(conf.backlight.pwm_ch, conf.backlight.freq, 0)
    pwm.start(conf.backlight.pwm_ch)
    gpio.setup(17, 0)      -- LCD 供电使能（低有效）
    gpio.setup(15, 1)      -- LCD_DISP
    gpio.setup(74, 1)      -- SD_EN 上电
    gpio.setup(73, 0)      -- 功放 PA 关断
    i2c.setup(1, 0, true)  -- GT911 轮询模式
    sys.wait(120)
end

local function backlight_on()
    pwm.setup(conf.backlight.pwm_ch, conf.backlight.freq, conf.backlight.duty)
    pwm.start(conf.backlight.pwm_ch)
    log.info("main", "背光已点亮", conf.backlight.duty .. "%")
end

local function touch_init()
    for attempt = 1, 2 do
        local dev = tp.init(conf.touch.model, {
            port = conf.touch.port,
            pin_rst = conf.touch.pin_rst,
            pin_int = conf.touch.pin_int,
            int_type = tp.FALLING,
            w = SW,
            h = SH,
        })
        if dev then
            airui.device_bind_touch(dev)
            log.info("main", "GT911 触摸初始化完成")
            return true
        end
        log.warn("main", "GT911 未就绪，200ms 后重试", attempt)
        sys.wait(200)
    end
    log.error("main", "触摸初始化失败")
    return false
end

sys.taskInit(function()
    local pc = is_pc()
    log.info("main", "运行环境", "IS_PC =", tostring(pc))

    -- 1、供电与引脚
    if not pc then power_on() end

    -- 2、显示初始化
    local ok, info = exd.setup({ pin_rst = conf.display.pin_rst })
    if not ok then
        log.error("main", "显示初始化失败", info)
        return
    end
    log.info("main", "显示初始化完成", info.backend, info.w, info.h)

    -- 3、AirUI
    if not airui.init(SW, SH) then
        log.error("main", "airui.init 失败")
        return
    end
    airui.set_rotation(conf.display.rotation)
    airui.font_load({
        type = "hzfont",
        size = conf.font.size,
        cache_size = conf.font.cache_size,
        antialias = conf.font.antialias,
    })

    -- 4、业务数据
    store.init()

    -- 5、主界面
    ui_main.build()

    -- 6、预构建浮层（z 序：表单 < 领取 < 输入 < 提示；键盘在 ui_input 内最后创建）
    ui_form.build()
    ui_claim.build()
    ui_input.build()
    ui_alert.build()

    -- 7、触摸
    if not pc then touch_init() end

    -- 8、背光
    if not pc then backlight_on() end

    -- 9、时钟每秒刷新
    ui_main.tick()
    sys.timerLoopStart(function()
        local ok2, err = pcall(ui_main.tick)
        if not ok2 then log.error("main", "时钟刷新异常", err) end
    end, 1000)

    log.info("main", "失物招领公示已就绪", PROJECT, VERSION, os.date("%Y-%m-%d %H:%M:%S"))
end)

sys.run()
