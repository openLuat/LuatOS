-- 核心库：display + airui + gpio + pins + i2c + tp；在 sys.taskInit 内调用。
-- 板级由 config.lua 的 C.BOARD_PROFILE 选择：
--   air8607_10i   Air8607(Air1603) + AirLCD_1100 10.1寸（JD9165BA，1024x600 RGB，GT911，PWM3 背光）
--   existing      Air8601 + 7寸 HX8282（原接线，PIN43/GPIO13 背光）
--   official_v010 Air8601 官方 factory 接线（PWM3 背光）
local C = require "config"
local M = {}

local function is_pc()
    return rtos and rtos.bsp and rtos.bsp() == "PC"
end

local function existing_power()
    pins.setup(43, "GPIO13")
    for _, s in ipairs({{42,1,50},{65,0,100},{65,1,1000},{43,1},{52,1},{56,1},{73,1,200}}) do
        gpio.setup(s[1], 0)
        gpio.set(s[1], s[2])
        if s[3] then sys.wait(s[3]) end
    end
end

local function v010_power()
    pins.setup(33, "I2C1_CLK")
    pins.setup(32, "I2C1_SDA")
    -- 官方 eng_8601_7i_4g/7i_wifi 两者的公共硬件上电参数。
    for _, s in ipairs({{65,1,1},{57,1,0,100},{73,0,1,200},{64,1,0,50},{15,0,1},{72,0,1}}) do
        gpio.setup(s[1], s[2])
        gpio.set(s[1], s[3])
        if s[4] then sys.wait(s[4]) end
    end
end

-- Air8607 上电：官方 factory 的 pins 段为空，使用默认复用；
-- 不驱动 Air8601 的 PIN43/PIN32/PIN33，也不预置 GPIO38（I2C1 SDA 交给 i2c 接管）。
-- SD_EN=GPIO74 拉高；AUDIOPA_EN=GPIO73 拉低关断未使用功放。
local function air8607_power()
    gpio.setup(74, 0)
    gpio.set(74, 1)
    gpio.setup(73, 0)
    gpio.set(73, 0)
    -- 背光 PWM3（PIN55/GPIO13）先以 0 占空比启动，首帧后由 backlight_on() 点亮
    if pwm and pwm.setup and pwm.start then
        pwm.setup(3, 1000, 0)
        pwm.start(3)
    end
end

-- JD9165BA 免初始化 IC（无 SPI 序列），走官方 exd_jd9165ba_rgb 扩展库
local function air8607_screen()
    local ok, info = require("exd_jd9165ba_rgb").setup({
        pin_rst = 15, screen_size = 10.1,
        w = C.WIDTH, h = C.HEIGHT, rotation = 0,
        hbp = 140, hspw = 20, hfp = 160,
        vbp = 20, vspw = 3, vfp = 12,
        bus_speed = 50000000,
    })
    if not ok then return false, tostring(info) end
    -- 后端可能为 display（优先）或 lcd（降级），优先以实际后端尺寸为准
    local w, h = info.w, info.h
    local backend = (info.backend == "display") and display or lcd
    if backend and backend.getSize then
        local ok2, gw, gh = pcall(backend.getSize)
        if ok2 and gw and gh then w, h = gw, gh end
    end
    if w ~= C.WIDTH or h ~= C.HEIGHT then
        return false, "JD9165BA 分辨率不符: " .. tostring(w) .. "x" .. tostring(h)
    end
    return true
end

function M.init()
    assert(airui and airui.init and airui.image, "固件缺少 AirUI 核心库")
    local pc = is_pc()
    if not pc then
        assert(gpio and i2c and tp, "固件缺少 GPIO/I2C/TP 核心库")
        if C.BOARD_PROFILE == "air8607_10i" then
            air8607_power()
            local ok, err = air8607_screen()
            assert(ok, "JD9165BA 初始化失败: " .. tostring(err))
        else
            assert(display and display.init, "请使用 Air1601 的102号固件（display核心库）")
            assert(pins, "固件缺少 PINS 核心库")
            if C.BOARD_PROFILE == "existing" then
                existing_power()
            elseif C.BOARD_PROFILE == "official_v010" then
                v010_power()
            else
                error("不支持的 BOARD_PROFILE: " .. tostring(C.BOARD_PROFILE))
            end
            local ok, err = display.init("custom", {
                id = 0, interface = "rgb", w = C.WIDTH, h = C.HEIGHT,
                hbp = 140, hspw = 20, hfp = 160,
                vbp = 20, vspw = 3, vfp = 12,
                pclk_hz = 50000000, pin_rst = 15,
            })
            assert(ok, "display.init: " .. tostring(err))
            local w, h = display.getSize()
            assert(w == C.WIDTH and h == C.HEIGHT, "屏幕尺寸应为1024x600")
        end
    end
    assert(airui.init(C.WIDTH, C.HEIGHT), "airui.init失败")
    M.font = airui.font_load({type = "hzfont", size = 20,
        cache_size = 1024, antialias = 1, global = true})
    assert(M.font, "无法加载固件内置hzfont中文字库")
    airui.set_rotation(0)
    if not pc then
        if C.BOARD_PROFILE == "air8607_10i" then
            -- 官方 tp_gt911：I2C1 轮询模式，RST=GPIO14，INT=GPIO51
            i2c.setup(1, 0, true)
            M.touch = tp.init("gt911", {port = 1, pin_rst = 14, pin_int = 51,
                int_type = tp.FALLING, w = C.WIDTH, h = C.HEIGHT})
            assert(M.touch, "GT911初始化失败，请核对 Air8607 触摸接线")
        elseif C.BOARD_PROFILE == "existing" then
            -- 与已有工程一致：SDA预置高，随后交给I2C1，之后不再操作GPIO38。
            gpio.setup(38, 0)
            gpio.set(38, 1)
            i2c.setup(1)
            M.touch = tp.init("gt911", {port = 1, pin_rst = 56, pin_int = 51,
                int_type = tp.FALLING, w = C.WIDTH, h = C.HEIGHT})
            assert(M.touch, "GT911初始化失败，请核对屏幕接线及BOARD_PROFILE")
        else
            i2c.setup(1, 0, true)
            M.touch = tp.init("gt911", {port = 1, pin_rst = 56, pin_int = 51,
                int_type = tp.FALLING, w = C.WIDTH, h = C.HEIGHT})
            assert(M.touch, "GT911初始化失败，请核对屏幕接线及BOARD_PROFILE")
        end
        assert(airui.device_bind_touch(M.touch), "AirUI绑定触摸失败")
    end
    -- 8607 走 PWM 背光：即使上层忘记调用 backlight_on，也兜底在首帧后点亮
    if not pc and C.BOARD_PROFILE == "air8607_10i" then
        sys.timerStart(function() M.backlight_on() end, 500)
    end
    log.info("board", "ready", C.BOARD_PROFILE, airui.version())
    return true
end

function M.backlight_on()
    if is_pc() then return end
    if C.BOARD_PROFILE == "air8607_10i" then
        assert(pwm and pwm.setDuty, "固件缺少PWM核心库")
        pwm.setDuty(3, C.BACKLIGHT_DUTY or 90)
    elseif C.BOARD_PROFILE == "official_v010" then
        assert(pwm and pwm.open, "固件缺少PWM核心库")
        pwm.open(3, 1000, C.BACKLIGHT_DUTY or 90)
    end
end
return M
