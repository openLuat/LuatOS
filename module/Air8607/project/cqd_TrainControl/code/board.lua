-- 板级由 config.lua 的 BOARD_PROFILE 选择，默认 air8607_10i：
--   air8607_10i  Air8607(Air1603) + AirLCD_1100 10.1寸 JD9165BA，1024x600 RGB + GT911 + PWM3 背光
--   air8601_7i   Air8601(Air1601) + 7寸 HX8282，1024x600 RGB + GT911，PIN43/GPIO13 背光
-- 两者都需要 display/airui 核心库；8607 走官方 exd_jd9165ba_rgb 扩展库（免初始化 IC）。
local M = {
    width = 1024,
    height = 600,
    profile = "air8607_10i",
    backlight_duty = 90,
}

local function is_pc()
    return rtos and rtos.bsp and rtos.bsp() == "PC"
end

-- Air8601 官方初始化顺序（PIN43 复用 GPIO13 作为背光驱动脚）
local function air8601_power_on()
    pins.setup(43, "GPIO13")
    local steps = {
        {42, 1, 50},
        {65, 0, 100},
        {65, 1, 1000},
        {43, 1},
        {52, 1},
        {56, 1},
        {73, 1, 200}
    }
    for _, step in ipairs(steps) do
        gpio.setup(step[1], 0)
        gpio.set(step[1], step[2])
        if step[3] then sys.wait(step[3]) end
    end
end

-- Air8607 官方 factory（eng_8607_10i_v0）：pins 段为空，使用默认复用；
-- SD_EN=GPIO74 拉高，AUDIOPA_EN=GPIO73 拉低关断未使用功放；
-- 背光 PWM3（PIN55/GPIO13）先以 0 占空比启动，首帧后点亮。
-- 不引用 Air8601 的 PIN43/PIN32/PIN33，也不预置 GPIO38（I2C1 SDA 交给 i2c 接管）。
local function air8607_power_on()
    gpio.setup(74, 0)
    gpio.set(74, 1)
    gpio.setup(73, 0)
    gpio.set(73, 0)
    if pwm and pwm.setup and pwm.start then
        pwm.setup(3, 1000, 0)
        pwm.start(3)
    end
end

-- Must run inside sys.taskInit, because the power sequence yields.
-- Returns true, width, height on success; false, message on failure.
function M.init(config)
    local profile = (config and config.BOARD_PROFILE) or M.profile
    if config and config.width then M.width = config.width end
    if config and config.height then M.height = config.height end
    if config and config.BACKLIGHT_DUTY then M.backlight_duty = config.BACKLIGHT_DUTY end
    M.profile = profile
    local pc = is_pc()

    if not (airui and airui.init) then
        return false, "airui core missing"
    end

    if not pc then
        if not (gpio and i2c and tp) then
            return false, "GPIO/I2C/TP core libraries are missing"
        end

        if profile == "air8607_10i" then
            air8607_power_on()
            local ok, info = require("exd_jd9165ba_rgb").setup({
                pin_rst = 15, screen_size = 10.1,
                w = M.width, h = M.height, rotation = 0,
                hbp = 140, hspw = 20, hfp = 160,
                vbp = 20, vspw = 3, vfp = 12,
                bus_speed = 50000000,
            })
            if not ok then return false, "JD9165BA init failed: " .. tostring(info) end
            -- 后端可能为 display（优先）或 lcd（降级），优先以实际后端尺寸为准
            local w, h = info.w, info.h
            local backend = (info.backend == "display") and display or lcd
            if backend and backend.getSize then
                local ok2, gw, gh = pcall(backend.getSize)
                if ok2 and gw and gh then w, h = gw, gh end
            end
            if w ~= M.width or h ~= M.height then
                return false, "unexpected screen size " .. tostring(w) .. "x" .. tostring(h)
            end
            log.info("board", "JD9165BA", info.backend, w, h)

        elseif profile == "air8601_7i" then
            if not display or not display.init then
                return false, "display core missing: use the official Air1601 102 firmware"
            end
            if not pins then return false, "pins core library is missing" end
            air8601_power_on()
            -- HX8282 uses RGB timings directly. id=0 is required for AirUI's screen.
            local ok, err = display.init("custom", {
                id = 0,
                interface = "rgb",
                w = M.width,
                h = M.height,
                hbp = 140,
                hspw = 20,
                hfp = 160,
                vbp = 20,
                vspw = 3,
                vfp = 12,
                pclk_hz = 50000000,
                pin_rst = 15
            })
            if not ok then return false, "display.init failed: " .. tostring(err) end
            -- display.init allocates its framebuffer; do not mix in lcd.setupBuff.
            local width, height = display.getSize()
            if width ~= M.width or height ~= M.height then
                return false, "unexpected screen size " .. tostring(width) .. "x" .. tostring(height)
            end

        else
            return false, "unsupported BOARD_PROFILE: " .. tostring(profile)
        end
    end

    if not airui.init(M.width, M.height) then return false, "airui.init failed" end

    local font_ok = airui.font_load({
        type = "hzfont",
        size = 16,
        cache_size = 1024,
        antialias = 1,
        global = true
    })
    if not font_ok then return false, "built-in hzfont load failed" end
    airui.set_rotation(0)

    if not pc then
        if profile == "air8607_10i" then
            -- 官方 tp_gt911：I2C1 轮询模式，RST=GPIO14，INT=GPIO51，显式宽高
            i2c.setup(1, 0, true)
            M.touch = tp.init("gt911", {
                port = 1,
                pin_rst = 14,
                pin_int = 51,
                int_type = tp.FALLING,
                w = M.width,
                h = M.height
            })
            if not M.touch then return false, "GT911 touch initialization failed (Air8607)" end
        else
            -- Air8601：SDA 预置高后交给 I2C1；GPIO38 不是背光脚
            gpio.setup(38, 0)
            gpio.set(38, 1)
            i2c.setup(1)
            M.touch = tp.init("gt911", {
                port = 1,
                pin_rst = 56,
                pin_int = 51,
                int_type = tp.FALLING,
                w = M.width,
                h = M.height
            })
            if not M.touch then return false, "GT911 touch initialization failed" end
        end
        if not airui.device_bind_touch(M.touch) then
            return false, "AirUI touch binding failed"
        end
        -- 8607 背光走 PWM：即使上层忘记调用 backlight_on，也兜底在首帧后点亮
        if profile == "air8607_10i" then
            sys.timerStart(function() M.backlight_on() end, 500)
        end
    end

    log.info("board", M.profile, "AirUI", airui.version())
    return true, M.width, M.height
end

function M.backlight_on()
    if is_pc() then return end
    if M.profile == "air8607_10i" and pwm and pwm.setDuty then
        pwm.setDuty(3, M.backlight_duty)
    end
end

return M
