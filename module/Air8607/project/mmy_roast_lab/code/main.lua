--[[
@module  main
@summary ROAST LAB 咖啡烘焙工坊入口（Air8607 10.1 寸 1024x600）
@version 1.0
@date    2026.10.30
@board   Air8607（Air1603）+ 10.1 寸 RGB 1024x600（免序列）+ GT911 电容触摸 + PWM3 背光
]]
PROJECT = "mmy_roast_lab"
VERSION = "1.0.0"

local conf = require "conf"
local theme = require "theme"
local exd = require "exd_air8607_rgb"
local app = require "app"

local SW, SH = conf.W, conf.H

local function power_on()
    pwm.setup(conf.backlight.pwm_ch, conf.backlight.freq, 0)
    pwm.start(conf.backlight.pwm_ch)

    gpio.setup(17, 0)   -- LCD 供电（低有效）
    gpio.setup(15, 1)   -- DISP
    gpio.setup(73, 0)   -- 功放关断

    -- GT911 I2C1：与 wpl_drying_room / air8607_demos 一致，400kHz 且不启用轮询模式
    i2c.setup(conf.touch.port, i2c.FAST)

    sys.wait(120)
end

local function backlight_on()
    local b = conf.backlight.default
    pwm.setup(conf.backlight.pwm_ch, conf.backlight.freq, b)
    pwm.start(conf.backlight.pwm_ch)
    log.info("main", "背光已点亮", b .. "%")
end

--[[GT911 触摸初始化 + airui 绑定（与 wpl_drying_room / air8607_demos 一致）

三个要点，改动任意一条都会出现"屏幕正常但点不动"：
1、I2C 在 power_on 里配置好，400kHz、不启用轮询模式；
2、tp.init 只调一次——内核 s_init 成功即置位，重试只会拿到 nil 并打印
   "tp has been initialized"，反而掩盖首次失败的真正原因；
3、绑定必须放在界面搭好之后，启动期 LVGL 首帧刷新与绑定撞车同样会点不动；
4、w/h 必须给，缺失会让 input 适配器以 EINVAL 静默拒绝。]]
local function touch_init()
    local tc = conf.touch
    local dev = tp.init("gt911", {
        port = tc.port,
        pin_rst = tc.pin_rst,
        pin_int = tc.pin_int,
        int_type = tp.FALLING,
        w = SW,
        h = SH,
    })
    if not dev then
        log.error("main", "触摸初始化失败：GT911 未应答（查供电 / RST=GPIO14 / INT=GPIO51 / 固件是否带 tp 库）")
        pcall(i2c.scan, tc.port, i2c.FAST)
        return false
    end
    local ok = airui.device_bind_touch(dev)
    log.info("main", "GT911 就绪，绑定 airui", ok and "ok" or "fail")
    return ok and true or false
end

-- hzfont 只按已加载的字号出字，界面上用到的字号必须全部载入（见 theme.SZ）
local function font_load_all()
    for _, sz in pairs(theme.SZ) do
        local ok = airui.font_load({
            type = "hzfont",
            size = sz,
            cache_size = conf.font.cache_size,
            antialias = conf.font.antialias,
        })
        if not ok then
            log.warn("main", "字号加载失败", sz)
        end
    end
end

sys.taskInit(function()
    power_on()

    local ok, info = exd.setup({ pin_rst = 15 })
    if not ok then
        log.error("main", "显示初始化失败", info)
        return
    end
    log.info("main", "显示初始化完成", info.backend, info.w, info.h)
    if info.backend ~= "display" then
        log.warn("main", "固件缺少 display 核心库（当前走旧 lcd 后端），建议升级 Air1603 V1028")
    end

    if not airui.init(SW, SH) then
        log.error("main", "airui.init 失败")
        return
    end
    airui.set_rotation(0)
    font_load_all()

    -- 顺序：建界面 → 绑触摸 → 起刷新循环 → 点背光
    -- 刷新循环一旦先跑起来，启动期重绘会和触摸绑定撞车，表现为"日志说完成但点不动"
    app.start()
    local touch_ok = touch_init()
    app.touch_debug()
    app.loop()

    backlight_on()
    if not touch_ok then
        app.toast("触摸初始化失败：请检查 GT911 接线", 0xE5624A)
    end
    log.info("main", conf.name .. " 已就绪")
end)

sys.run()
