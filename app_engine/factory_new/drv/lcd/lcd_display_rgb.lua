--[[
@module  lcd_display_rgb
@summary RGB 屏统一通过 display 库初始化（替代 lcd.init）
@version 3.0
@date    2026.09.18
@usage
params 透传给 display.init("custom", ...)：
  w, h, hbp, hspw, hfp, vbp, vspw, vfp, pclk_hz / bus_speed,
  pin_rst, pin_bl, pin_pwr, interface

可选 SPI IC 初始化（NV3052C/ST7701S/GC9503 等需要 SPI 寄存器配置的 RGB IC）：
  pin_clk, pin_sda, pin_cs  → SPI 总线引脚（对应 display.init 的 pin_scl/pin_sdi/pin_cs）
  ic_init                    → function(params) 返回 custom_cmds 表

display.init 内部自动完成:
  1. 通过 pin_cs/pin_scl/pin_sdi 建立 SPI 通道
  2. 发送 custom_cmds 中的 IC 寄存器序列
  3. 初始化 RGB 接口（时序参数）
  4. 分配 FrameBuffer

PC 模拟器 AirUI 走 SDL2，跳过 display.init 避免双窗口。
]]
local M = {}

function M.init(params)
    if params.pin_pwr then
        gpio.setup(params.pin_pwr, 1)
        gpio.set(params.pin_pwr, 1)
    end
    if params.pin_bl then
        gpio.setup(params.pin_bl, 1)
        gpio.set(params.pin_bl, 1)
    end

    if rtos.bsp() == "PC" then
        log.info("lcd_display_rgb", "PC sim skip display.init")
        return true
    end

    if not display or not display.init then
        log.error("lcd_display_rgb", "display 模块不存在，请使用带 LUAT_USE_DISPLAY 的固件")
        return false
    end

    -- 构建 display.init 配置
    local cfg = {
        id        = 0,
        interface = params.interface or "rgb",
        w         = params.w,
        h         = params.h,
        -- RGB 时序
        hbp       = params.hbp,
        hspw      = params.hspw,
        hfp       = params.hfp,
        vbp       = params.vbp,
        vspw      = params.vspw,
        vfp       = params.vfp,
        pclk_hz   = params.pclk_hz or params.bus_speed,
        -- 引脚
        pin_rst   = params.pin_rst,
        pin_bl    = params.pin_bl or params.pin_pwr,
        pin_pwr   = params.pin_pwr,
    }

    -- 可选: SPI IC 初始化（返回 custom_cmds 表，由 display.init 内部发送）
    if type(params.ic_init) == "function" then
        local cmds = params.ic_init(params)
        if cmds then
            cfg.custom_cmds = cmds
            -- SPI 引脚（display.init 内部用于发送 custom_cmds）
            if params.pin_cs then
                cfg.pin_cs  = params.pin_cs
            end
            if params.pin_clk then
                cfg.pin_scl = params.pin_clk
            end
            if params.pin_sda then
                cfg.pin_sdi = params.pin_sda
            end
            log.info("lcd_display_rgb", "IC custom_cmds 已加载, SPI pins: cs=" .. (params.pin_cs or "nil") ..
                     " scl=" .. (params.pin_clk or "nil") .. " sdi=" .. (params.pin_sda or "nil"))
        end
    end

    local r, err = display.init("custom", cfg)
    log.info("lcd_display_rgb", "display.init", r, err)
    if r then
        local addr, fb_size, fb_count = display.getFbInfo()
        log.info("lcd_display_rgb", "getFbInfo", addr, fb_size, fb_count)
    end
    return r
end

return M
