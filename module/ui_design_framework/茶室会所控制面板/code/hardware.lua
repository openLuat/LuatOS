--[[
硬件初始化：Air8607 + 官方 10.1 寸（JD9165BA，1024x600，GT911，PWM3 背光）
固件缺任一核心库时直接返回 false，由 main 打印原因
]]

local M = {}

local tp_gt911 = require "tp_gt911"

M.pwm_ch = 3

local function is_pc()
    return rtos and rtos.bsp and rtos.bsp() == "PC"
end

-- Air8607 上电：SD_EN 拉高、功放使能拉低、背光 PWM3 先 0 占空比
local function power_on()
    gpio.setup(74, 0)
    gpio.set(74, 1)
    gpio.setup(73, 0)
    gpio.set(73, 0)
    if pwm and pwm.setup and pwm.start then
        pwm.setup(M.pwm_ch, 1000, 0)
        pwm.start(M.pwm_ch)
    end
    log.info("hw", "GPIO 上电完成")
end

local function init_airui(w, h)
    local ok = airui.init(w, h)
    log.info("hw", "airui.init", ok, w, h)
    if not ok then return false end
    --[[
    load_to_psram：把渲染好的字形放进 PSRAM。
    不开时，字形缓存没命中就要回 .ttf 文件里搜（官方给的量级是 100ms/字，
    命中后 1ms/字）——重建页面时每个"没缓存过的字"都吃这一刀，
    表现就是"点开一页要顿一下"，且越少出现过的页面越慢。
    代价：每个字最多 100B，2048 字上限 ≈ 200KB PSRAM（板上有 12MB）。
    失败必须回退：拷不进 PSRAM 时 font_load 返回 nil，若不兜底 G_HZFONT
    会变 false，全局退回 16 号点阵，整个界面字都变小。
    ]]
    local base = { type = "hzfont", size = 16, cache_size = 2048, antialias = 1 }
    local fok = airui.font_load({
        type = "hzfont", size = 16, cache_size = 2048, antialias = 1,
        load_to_psram = true,
    })
    if not fok then
        log.warn("hw", "字库进 PSRAM 失败，退回按需读取（会慢，但界面完整）")
        fok = airui.font_load(base)
    end
    log.info("hw", "font_load hzfont", fok)
    G_HZFONT = (fok ~= nil and fok ~= false)
    airui.set_rotation(0)
    return true
end

local function init_screen()
    local ok, info = require("exd_jd9165ba_rgb").setup({
        pin_rst = 15,
        screen_size = 10.1,
        w = 1024, h = 600,
        rotation = 0,
        hbp = 140, hspw = 20, hfp = 160,
        vbp = 20, vspw = 3, vfp = 12,
        bus_speed = 50000000,
    })
    log.info("hw", "JD9165BA setup", ok, type(info) == "table" and info.backend or info)
    if not ok then return false end

    local w, h = info.w, info.h
    local backend = (info.backend == "display") and display or lcd
    if backend and backend.getSize then
        local ok2, gw, gh = pcall(backend.getSize)
        if ok2 and gw and gh then w, h = gw, gh end
    end
    log.info("hw", "screen", w, h)
    return init_airui(w, h)
end

local function init_touch()
    -- 与官方工程一致：i2c.setup(id, speed, ...) 三参形式，speed=0 用默认速率
    i2c.setup(1, 0, true)
    local ok = tp_gt911.init({
        port = 1,
        int_type = tp.FALLING,
        w = 1024, h = 600,
        pin_rst = 14,
        pin_int = 51,
    })
    log.info("hw", "tp.init", ok)
    if not ok then
        -- TP 没起来时界面照常显示但整屏点不动，这里必须喊出来，
        -- 否则只能靠猜（airui 侧不会有任何报错）
        log.error("hw", "触摸初始化失败：检查 GT911 接线 / I2C1 / RST(14) / INT(51)")
    end
    return ok
end

function M.set_brightness(v)
    M.brightness = v
    if is_pc() then return end
    if pwm and pwm.setDuty then
        pwm.setDuty(M.pwm_ch, math.max(0, math.min(100, v)))
    end
end

function M.init()
    local pc = is_pc()
    if not pc then
        if not (gpio and i2c and tp and pwm) then
            log.error("hw", "固件缺少 GPIO/I2C/TP/PWM 核心库")
            return false
        end
        power_on()
        --[[
        兜底点亮，只在异常路径上生效。

        正常路径由 ui.start() 在建树、首帧刷出之后点亮（见 ui.lua），
        因为 RGB 屏一上电就在扫帧缓冲，而这块 buffer 里是 PSRAM 的
        未初始化内容：背光早于首帧打开 = 直接把一屏随机数据照给用户，
        就是"进入时花一下"。

        这里留 4s 兜底：UI 若崩在建树里，背光仍会亮，配合串口日志能
        看出是界面没画出来，而不是"完全没背光"分不清。
        ]]
        sys.timerStart(function() M.set_brightness(M.brightness or 100) end, 4000)
    end

    local ok
    if pc then
        ok = init_airui(1024, 600)
    else
        ok = init_screen()
    end
    if not ok then
        log.error("hw", "屏幕/AirUI 初始化失败，背光已点亮，可依据上面日志定位")
        return false
    end

    if not pc then
        init_touch()
    end
    return true
end

return M
