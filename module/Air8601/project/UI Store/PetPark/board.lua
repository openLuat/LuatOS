-- 核心库：display + airui + gpio + pins + i2c + tp；在 sys.taskInit 内调用。
-- RGB 参数依据合宙 Air8601 factory；existing 接线与用户现有工程保持一致。
local C = require "config"
local M = {}

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

function M.init()
    assert(airui and airui.init and airui.image, "固件缺少 AirUI 核心库")
    local pc = rtos and rtos.bsp and rtos.bsp() == "PC"
    if not pc then
        assert(display and display.init, "请使用 Air1601 的102号固件（display核心库）")
        assert(gpio and pins and i2c and tp, "固件缺少 GPIO/PINS/I2C/TP 核心库")
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
    assert(airui.init(C.WIDTH, C.HEIGHT), "airui.init失败")
    M.font = airui.font_load({type = "hzfont", size = 20,
        cache_size = 1024, antialias = 1, global = true})
    assert(M.font, "无法加载固件内置hzfont中文字库")
    airui.set_rotation(0)
    if not pc then
        if C.BOARD_PROFILE == "existing" then
            -- 与已有工程一致：SDA预置高，随后交给I2C1，之后不再操作GPIO38。
            gpio.setup(38, 0)
            gpio.set(38, 1)
            i2c.setup(1)
        else
            i2c.setup(1, 0, true)
        end
        M.touch = tp.init("gt911", {port = 1, pin_rst = 56, pin_int = 51,
            int_type = tp.FALLING, w = C.WIDTH, h = C.HEIGHT})
        assert(M.touch, "GT911初始化失败，请核对屏幕接线及BOARD_PROFILE")
        assert(airui.device_bind_touch(M.touch), "AirUI绑定触摸失败")
    end
    log.info("board", "ready", C.BOARD_PROFILE, airui.version())
    return true
end

function M.backlight_on()
    if C.BOARD_PROFILE == "official_v010" and not (rtos and rtos.bsp() == "PC") then
        assert(pwm and pwm.open, "固件缺少PWM核心库")
        pwm.open(3, 1000, 90)
    end
end
return M
