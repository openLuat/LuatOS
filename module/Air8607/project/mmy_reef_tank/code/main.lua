--[[
@module  main
@summary ReefOS 珊瑚礁生态缸大屏入口（Air8607 10.1 寸 1024x600）
@version 1.0
@date    2026.10.27
@board   Air8607（Air1603）+ 10.1 寸 RGB 1024x600（免序列）+ GT911 电容触摸 + PWM3 背光
]]
PROJECT = "mmy_reef_tank"
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

    sys.wait(120)
end

local function backlight_on()
    local b = conf.backlight.default
    pwm.setup(conf.backlight.pwm_ch, conf.backlight.freq, b)
    pwm.start(conf.backlight.pwm_ch)
    log.info("main", "背光已点亮", b .. "%")
end

--[[GT911 触摸初始化（顺序：复位 → I2C 轮询 → tp.init → airui 绑定）

必须早于 UI 构建与动画任务：tp.init 要在 I2C 空闲时读产品 ID，
界面先跑起来会抢总线，读不出 ID 就返回 nil，表现就是"屏幕正常但点不动"。]]
local function touch_init()
    local tc = conf.touch

    if tc.gpio_reset then
        gpio.setup(tc.gpio_reset, 0)
        gpio.close(tc.gpio_reset)
    end

    -- 轮询模式（第三参 true）：坐标在 TP 中断路径里突发读，中断驱动 I2C 与嵌套中断
    -- 互相干扰时会"只有触摸时才报 I2C 错误"，轮询可根治；触摸带宽极小，性能无感。
    i2c.setup(tc.port, i2c.FAST, tc.polling ~= false)

    local dev
    for attempt = 1, 3 do
        dev = tp.init("gt911", {
            port = tc.port,
            pin_rst = tc.pin_rst,
            pin_int = tc.pin_int,
            int_type = tp.FALLING,
            w = SW,
            h = SH,
        })
        if dev then break end
        log.warn("main", "GT911 未应答，200ms 后重试", attempt)
        sys.wait(200)
    end
    if not dev then
        log.error("main", "触摸初始化失败：GT911 未应答（查供电/RST=GPIO14/INT=GPIO51/固件是否带 tp 库）")
        -- 扫一遍 I2C1：应能看到 0x5D（或复位拉低时 0x14），看不到就是硬件/供电问题
        pcall(i2c.scan, tc.port, i2c.FAST)
        return false
    end

    local ok = airui.device_bind_touch(dev)
    log.info("main", "GT911 就绪，绑定 airui", ok and "ok" or "fail")
    return true
end

-- 触摸坐标自检：能打印坐标说明驱动有数据，问题在 UI 层；完全没日志则是驱动/接线
local function touch_probe()
    if not conf.touch.debug then return end
    local names = { [0] = "NONE", "DOWN", "HOLD", "UP" }
    local ok = airui.touch_subscribe(function(state, x, y)
        log.info("touch", (names[state] or state) .. " x=" .. tostring(x) .. " y=" .. tostring(y))
    end)
    if not ok then log.warn("main", "touch_subscribe 不可用，跳过触摸自检") end
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

    -- 触摸先于界面：UI 构建要几百毫秒，动画任务也会占总线
    local touch_ok = touch_init()

    app.start()
    touch_probe()

    backlight_on()
    if not touch_ok then
        app.toast("触摸初始化失败：请检查 GT911 接线", 0xE5624A)
    end
    log.info("main", conf.name .. " 已就绪")
end)

sys.run()
