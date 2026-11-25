--[[
@module  hardware
@summary 硬件初始化（Air1603_A10 / 引擎 AIR8603M1 10 寸 1024x600：JD9165BA + GT911，兼容 Air8607）
@version 2.0.0
@usage
  hardware.init_density_scale()  -- 需在 require 界面模块前调用
  hardware.init()                -- 上电 + 屏幕 + AirUI + 触摸（必须在 sys.taskInit 里）
  hardware.backlight_on()        -- 首帧之后再点背光，避免看到花屏/黑屏闪烁
@note 顺序不可改：GPIO/电源轨上电 → LCD(display) → airui.init → hzfont → 触摸 → 背光。
      跑在哪块板上由 rtos.bsp() 判断：
        PC            → 只 airui.init（SDL 渲染）
        Air1603（A10）→ 5V/9V/12V/5VOUT 电源轨 + TP_RST(GPIO72) + SD_EN + PWM3 背光
        Air8607       → SD_EN(GPIO74) + AUDIOPA_EN(GPIO73) + PWM3 背光
      必需步骤失败都要 log.error 出「阶段 + 原始错误」后返回 false，由 main 终止启动。
]]
local M = {}

local tp_gt911 = require "tp_gt911"

local function bsp_name()
    local ok, b = pcall(function() return rtos.bsp() end)
    if ok and type(b) == "string" then return b end
    return "unknown"
end

local function is_pc()
    return bsp_name() == "PC"
end

--- 屏幕密度缩放（以 1024x600 为设计基准；本工程坐标全部按 1.0 写死，仅用于日志确认）
function M.init_density_scale()
    _G.density_scale = 1
    local ok, w, h = pcall(function() return display.getSize() end)
    if ok and type(w) == "number" and w > 0 and type(h) == "number" and h > 0 then
        _G.density_scale = math.min(w / 1024, h / 600)
    end
    log.info("hardware", "屏幕密度缩放系数", _G.density_scale)
end

-- ==================== 上电 ====================

--- 拉高一个供电/使能脚（失败不阻断：不同底板引出的脚不一样）
local function gpio_hi(pin)
    pcall(function()
        gpio.setup(pin, 0)
        gpio.set(pin, 1)
    end)
end

--- 背光 PWM 先压 0 占空比，避免上电背光提前亮（首帧后再点亮）
--- 注意：本固件 pwm.setup 里有一句无条件的 `E/pwm setup ch 3` 调试日志，
---       它不代表失败（返回 true 才算成功），看到这行不用管。
local function backlight_hold()
    if not (pwm and pwm.setup and pwm.start) then return end
    local ok, ret = pcall(function()
        pwm.setup(3, 1000, 0)
        pwm.start(3)
        return true
    end)
    if not (ok and ret) then
        log.warn("hardware", "PWM3 背光 setup 失败（灯可能不亮，但界面照常跑）", tostring(ret))
    end
end

--[[
Air1603_A10（引擎 AIR8603M1 10 寸，官方 project/factory/config/eng_8603m_10i_v0.lua）：
  5V_EN=GPIO12 / 9V_EN=GPIO56 / 12V_EN=GPIO44 / 5VOUT_EN=GPIO52 / SD_EN=GPIO74 /
  AUDIOPA_EN=GPIO73（本板是 Air1103 供电脚，高电平常供电）/ TP_RST=GPIO72。
  12V 是背光升压的输入，缺了这一路背光就不亮 —— 这是「屏不亮」最常见的原因。
]]
local function power_on_1603()
    -- 触摸复位脉冲：低 20ms → 高 60ms（GT911 靠这 60ms 启动并锁 I2C 地址）
    pcall(function()
        gpio.setup(72, 0)
        gpio.set(72, 0)
    end)
    sys.wait(20)
    pcall(function() gpio.set(72, 1) end)
    sys.wait(60)

    gpio_hi(12)                 -- 5V
    gpio_hi(56)                 -- 9V
    sys.wait(100)
    gpio_hi(44)                 -- 12V（背光升压）
    gpio_hi(52)                 -- 对外 5V 输出
    gpio_hi(74)                 -- SD_EN
    gpio_hi(73)                 -- AUDIOPA_EN / Air1103 供电

    backlight_hold()
    log.info("hardware", "GPIO 上电完成（Air1603_A10，5V=12 / 9V=56 / 12V=44 / 5VOUT=52 / SD_EN=74 / TP_RST=72 / PWM3=0）")
end

-- ===== Air8607 上电：SD_EN(GPIO74) 拉高、AUDIOPA_EN(GPIO73) 拉低、背光 PWM3 先 0 占空比 =====
-- 官方 factory 的 pins 段为空，使用默认复用；不预置 GPIO38（I2C1 SDA 交给 i2c 接管）。
local function power_on_8607()
    pcall(function()
        gpio.setup(74, 0)
        gpio.set(74, 1)
        gpio.setup(73, 0)
        gpio.set(73, 0)
    end)
    backlight_hold()
    log.info("hardware", "GPIO 上电完成（Air8607，SD_EN=1 / AUDIOPA_EN=0 / PWM3=0）")
end

-- ==================== 屏幕 / AirUI ====================

local function init_airui(w, h)
    local ok, ret = pcall(airui.init, w, h)
    log.info("hardware", "airui.init", ok, ret, w, h)
    if not (ok and ret) then
        log.error("hardware", "airui.init 失败（阶段=AirUI 初始化）", tostring(ret))
        return false
    end

    -- 中文矢量字库：12-255 号全覆盖，本工程最小 16 号
    local fok, ferr = pcall(airui.font_load, {
        type = "hzfont", size = 20, cache_size = 2048, antialias = 1,
    })
    if not fok then
        log.error("hardware", "airui.font_load 失败（阶段=字库加载）", tostring(ferr))
        return false
    end
    pcall(function() airui.set_rotation(0) end)
    return true
end

-- ===== JD9165BA：免初始化 IC，只做复位 + RGB 时序（两块板都是 pin_rst=GPIO15 / 1024x600）=====
local function init_screen()
    local lok, info = pcall(require("exd_jd9165ba_rgb").setup, {
        pin_rst     = 15,
        screen_size = 10.1,
        w           = 1024,
        h           = 600,
        rotation    = 0,
        hbp         = 140,
        hspw        = 20,
        hfp         = 160,
        vbp         = 20,
        vspw        = 3,
        vfp         = 12,
        bus_speed   = 50 * 1000 * 1000,
    })
    if not lok then
        log.error("hardware", "LCD 初始化失败（阶段=JD9165BA display.init）", tostring(info))
        return false
    end
    -- setup 的返回值有两种形态：成功时 (true, info表)，某些版本/分支只回 true。
    -- 这里绝不能用 if info.backend 直接取（info 可能是 boolean，会抛
    -- attempt to index a boolean value，屏幕就再也点不亮了）。
    local t = type(info) == "table" and info or {}
    log.info("hardware", "JD9165BA display.init", true, t.backend or "", t.w or "-", t.h or "-")
    local w = (type(t.w) == "number" and t.w > 0) and t.w or 1024
    local h = (type(t.h) == "number" and t.h > 0) and t.h or 600
    log.info("hardware", "屏幕尺寸", w, h)
    return init_airui(w, h)
end

-- ==================== 触摸 ====================

--- GT911：Air1603_A10 是 TP_RST=GPIO72 / TP_INT=GPIO51，Air8607 是 GPIO14 / GPIO51
local function init_touch(pin_rst)
    local ok, ret = pcall(function()
        i2c.setup(1)
        return tp_gt911.init({ port = 1, int_type = tp.FALLING, w = 1024, h = 600,
            pin_rst = pin_rst, pin_int = 51 })
    end)
    log.info("hardware", "tp.init", ok, ret, "pin_rst=" .. tostring(pin_rst))
    if not (ok and ret) then
        -- 触摸失败不终止启动：屏能亮、界面能看到，才好判断是接线还是驱动问题
        log.error("hardware", "触摸初始化失败（阶段=GT911，界面可见但无法点击）",
            "pin_rst=" .. tostring(pin_rst), tostring(ret))
        return false
    end
    return true
end

--- 背光点亮（Air1603/Air8607 都走 PWM3；PC 模拟器无背光）
function M.backlight_on()
    if is_pc() then return end
    if pwm and pwm.setDuty then
        local ok, ret = pcall(function()
            pwm.setDuty(3, 90)
            return true
        end)
        if ok and ret then
            log.info("hardware", "背光已点亮（PWM3 duty=90）")
        else
            log.error("hardware", "背光点亮失败（PWM3 setDuty=90）", tostring(ret))
        end
    else
        log.error("hardware", "固件无 pwm.setDuty，无法点亮背光")
    end
end

--- 硬件总初始化，失败返回 false（调用方必须终止启动）
function M.init()
    local bsp = bsp_name()
    log.info("hardware", "bsp", bsp)

    if bsp == "PC" then
        log.info("hardware", "PC 模拟器：跳过 GPIO/触摸，直接 airui.init(1024,600)")
        return init_airui(1024, 600)
    end

    if not (gpio and i2c and tp and display) then
        log.error("hardware", "固件缺少 GPIO/I2C/TP/DISPLAY 核心库")
        return false
    end

    local tp_rst = 14
    if bsp:find("1603") or bsp:find("8603") then
        power_on_1603()
        tp_rst = 72
    else
        power_on_8607()
    end

    if not init_screen() then
        return false
    end
    init_touch(tp_rst)          -- 失败只降级（无触摸），不阻断出图与背光

    -- 兜底：上层若忘记调 backlight_on，首帧后 500ms 也能亮
    sys.timerStart(function() M.backlight_on() end, 500)
    return true
end

return M
