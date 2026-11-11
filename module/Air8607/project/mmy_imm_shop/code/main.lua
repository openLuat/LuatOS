--[[
@module  main
@summary 注塑车间工艺监控终端（Air8607 + 10.1 寸 1024x600 RGB + GT911 触摸）
@version 1.0.0
@date    2026.11.10
@board   Air8607 / Air1603
         硬件引脚与 module/Air8607/project/factory/config/eng_8607_10i_v0.lua 对齐：
           LCD 复位 pin_rst = 15   LCD 供电 pin_pwr = 17
           背光 PWM3（GPIO13）      触摸 I2C1（400kHz）pin_rst = 14 pin_int = 51
@usage
启动顺序：
1、power_on()      供电 / PWM3 占空比 0 / I2C1 引脚
2、exd.setup()     显示 IC 初始化（复位 + RGB 时序 + 帧缓冲）
3、airui.init()    分辨率 + 中文字体
4、ui.start()      顶栏 + 5 页面（总览/工艺/模具工单/报警/设置）
5、touch_init()    GT911 触摸绑定
6、backlight_on()  点亮背光
7、ui 内部启动 1Hz 循环：工艺仿真 + 数据刷新 + 自动轮播
]]
PROJECT = "imm_shop"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- ==================== 真机脚本打包诊断（问题定位后可整段删除） ====================
-- PC 模拟器直接读源码目录，真机走 luadb 打包，两者文件集合可能不一致。
-- 这里在 require 之前先把设备上真实存在的脚本列出来，方便对照。
do
    for _, d in ipairs({ "/", "/luadb" }) do
        local ok, list = pcall(io.lsdir, d, 64)
        if ok and type(list) == "table" then
            local names = {}
            for _, n in ipairs(list) do
                if type(n) == "table" then n = n.name or "?" end
                names[#names + 1] = tostring(n)
            end
            log.info("fs", "目录", d, #names, table.concat(names, " "))
        else
            log.warn("fs", "目录不可读", d, tostring(list))
        end
    end

    local FILES = {
        "main", "conf", "theme", "store", "model", "exd_air8607_rgb", "ui",
        "ui_overview", "ui_process", "ui_mold", "ui_alarm", "ui_settings",
    }
    local DIRS = { "", "/luadb", "/lua" }
    local miss = 0
    for _, f in ipairs(FILES) do
        local hit
        for _, d in ipairs(DIRS) do
            for _, ext in ipairs({ ".lua", ".luac" }) do
                local path = d .. "/" .. f .. ext
                local ok, e = pcall(io.exists, path)
                if ok and e then hit = path break end
            end
            if hit then break end
        end
        if hit then
            log.info("fs", "命中", f, hit)
        else
            miss = miss + 1
            log.error("fs", "缺失", f)
        end
    end
    log.info("fs", "脚本检查完成，缺失", miss, "个")
end
-- ==================================================================================

local conf  = require("conf")
local ui    = require("ui")
local store = require("store")
local exd   = require("exd_air8607_rgb")

local SCREEN_W, SCREEN_H = conf.W, conf.H

local function power_on()
    pcall(function()
        pwm.setup(conf.backlight.pwm_ch, conf.backlight.freq, 0)
        pwm.start(conf.backlight.pwm_ch)
    end)
    -- 注意：本板 LCD 没有独立供电使能脚，factory/config/eng_8607_10i_v0.lua 的 power_on
    -- 只处理 SD_EN(74) 与 AUDIOPA_EN(73)。此前写的 GPIO17 在 Air1603 上不可用
    -- （日志：luat_gpio_open pin 17 disable use / gpio setup fail ret -1），已移除。
    -- LCD_DISP(GPIO15) 由 display.init 的 pin_rst 时序接管，外部不再手动操作。
    pcall(function()
        i2c.setup(1, i2c.FAST)
    end)
    sys.wait(100)
end

local function backlight_on()
    -- 优先使用设置页保存的亮度
    local duty = conf.backlight.default
    local okc, v = pcall(function() return store.settings().backlight end)
    if okc and type(v) == "number" and v > 0 then duty = v end
    local ok = pcall(function()
        pwm.setup(conf.backlight.pwm_ch, conf.backlight.freq, duty)
        pwm.start(conf.backlight.pwm_ch)
    end)
    log.info("main", ok and ("背光已点亮 " .. duty .. "%") or "背光初始化失败")
end

local function touch_init()
    if not tp or not tp.init then
        log.warn("main", "固件无 tp 库，触摸不可用")
        return false
    end
    local ok, dev = pcall(tp.init, "gt911", {
        port = 1, pin_rst = 14, pin_int = 51,
        int_type = tp.FALLING, w = SCREEN_W, h = SCREEN_H,
    })
    if ok and dev then
        if airui.device_bind_touch then
            pcall(airui.device_bind_touch, dev)
        end
        log.info("main", "GT911 触摸初始化完成")
        return true
    end
    log.error("main", "触摸初始化失败", tostring(dev))
    return false
end

sys.taskInit(function()
    power_on()

    local ok, info = exd.setup({ pin_rst = 15 })
    if not ok then
        log.error("main", "显示初始化失败", info)
        return
    end
    log.info("main", "显示初始化完成", info.backend, info.w, info.h)

    if not airui.init(SCREEN_W, SCREEN_H) then
        log.error("main", "airui.init 失败")
        return
    end
    airui.set_rotation(0)
    airui.font_load({
        type = "hzfont", size = conf.font.size,
        cache_size = conf.font.cache_size, antialias = conf.font.antialias,
    })

    local root = airui.container({
        x = 0, y = 0, w = SCREEN_W, h = SCREEN_H,
        color = 0x0B1017, radius = 0,
    })
    local ok_ui, err_ui = pcall(ui.start, root)
    if not ok_ui then
        log.error("main", "界面启动失败", tostring(err_ui))
    end

    touch_init()
    sys.wait(120)
    backlight_on()

    log.info("main", conf.name .. " 已就绪")
end)

sys.run()
