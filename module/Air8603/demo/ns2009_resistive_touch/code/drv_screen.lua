--[[
@module  drv_screen
@summary 屏幕：真机 display.init 分配 RGB 帧缓冲（供 AirUI 使用）+ PWM 背光
@version 1.0
@date    2026.11.11
@usage
  local drv = require("drv_screen")
  drv.set_backlight_cfg(CFG.backlight); drv.backlight(0)
  drv.init(CFG.lcd)          -- 真机 display.init 分配 FB；PC 跳过（SDL2 自管窗口）
  drv.width(); drv.height()  -- 实际分辨率
  drv.backlight(0..100)

说明：
  点屏/刷新/绘制全部交给 AirUI（LVGL 每帧自刷 FB），本模块不再做绘制封装、
  也不再手动 display.flush。真机 AirUI(LUATOS) 依赖 display.init 已注册的 FB，
  所以 init 必须先于 airui.init 跑。
  PC 模拟器下 airui 走 SDL2 窗口自管显示，重复 display.init 会冲突，所以跳过。
]]

local drv = {}

drv.is_pc = false

local bl_cfg = { pwm_ch = 3, pwm_freq = 1000 }
local screen_w, screen_h = 800, 480
local inited = false

--[[当前是否 PC 模拟器]]
local function detect_pc()
    if rtos and rtos.bsp then
        local ok, bsp = pcall(rtos.bsp)
        if ok and bsp == "PC" then return true end
    end
    return false
end

--[[
初始化屏幕
  真机：display.init("custom", {interface="rgb", ...}) 分配 FB（AirUI 随后使用）
  PC  ：跳过 display.init，尺寸由配置决定（SDL2 自管窗口）
@param table c  CFG.lcd
@return boolean 是否成功
]]
function drv.init(c)
    drv.is_pc = detect_pc()

    if drv.is_pc then
        screen_w, screen_h = c.w, c.h
        inited = true
        log.info("screen", "PC 模拟器：跳过 display.init，窗口尺寸", screen_w .. "x" .. screen_h)
        return true
    end

    if not (display and display.init) then
        log.error("screen", "固件没有 display 库，无法分配 FB")
        return false
    end

    local params = {
        id = 0,
        interface = "rgb",
        w = c.w, h = c.h,
        hbp = c.hbp, hspw = c.hspw, hfp = c.hfp,
        vbp = c.vbp, vspw = c.vspw, vfp = c.vfp,
        pclk_hz = c.bus_speed,
    }
    if c.pin_rst and c.pin_rst ~= 0xFF then params.pin_rst = c.pin_rst end

    local ok, err = display.init("custom", params)
    log.info("screen", "display.init(rgb)", ok, err, c.w .. "x" .. c.h)
    if ok ~= true then
        return false
    end

    screen_w, screen_h = c.w, c.h
    if display.getSize then
        local dw, dh = display.getSize()
        if dw and dw > 0 then screen_w, screen_h = dw, dh end
    end
    inited = true
    return true
end

--[[背光配置（PWM 通道/频率）]]
function drv.set_backlight_cfg(bl)
    if type(bl) == "table" then
        bl_cfg.pwm_ch   = bl.pwm_ch or bl_cfg.pwm_ch
        bl_cfg.pwm_freq = bl.pwm_freq or bl_cfg.pwm_freq
    end
end

--[[背光：PWM 调光，0 = 熄灭（PC 模拟器没有背光，直接跳过）]]
function drv.backlight(level)
    if drv.is_pc then return end
    level = math.max(0, math.min(100, math.floor(level or 100)))
    if pwm and pwm.setup then
        pcall(pwm.setup, bl_cfg.pwm_ch, bl_cfg.pwm_freq, level)
        pcall(pwm.start, bl_cfg.pwm_ch)
        log.info("screen", "背光", "ch" .. bl_cfg.pwm_ch, level .. "%")
    else
        log.warn("screen", "固件没有 pwm 库，背光未驱动")
    end
end

function drv.width()  return screen_w end
function drv.height() return screen_h end

return drv
