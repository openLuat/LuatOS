--[[
@module  lcd_display_rgb
@summary RGB 屏统一通过 display 库初始化（替代 lcd.init）
@version 3.1
@date    2026.09.28
@usage
params 透传给 display.init("custom", ...)：
  w, h, hbp, hspw, hfp, vbp, vspw, vfp, pclk_hz / bus_speed,
  pin_rst, interface

供电/背光引脚策略（pin_pwr / pin_bl 不透传给 display.init，由本模块统一驱动）：
  pin_pwr  屏供电使能，init 即拉高（SPI ic_init 发寄存器前屏必须有电）
  pin_bl   背光使能，init 时压低延后，由 boot_ui 首帧上屏后的 backlight_on
           收口点亮 —— RGB 帧缓冲跨热复位不清屏，提前亮会把残留画面闪给用户
  同脚特例(pin_bl == pin_pwr)：无 ic_init 时整体按背光延后（纯 RGB 时序初始化
           不依赖屏上电，首帧刷入帧缓冲后一起开电+背光，同样无残影）；
           有 ic_init 时只能提前上电（寄存器要靠 SPI 写入），闪屏无法避免
  不透传的原因：display.init 末尾会 display_on 无条件拉高 pin_bl/pin_pwr
  （luat_lib_display.c "默认开启显示"），会架空延后开背光的时序

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
    -- 供电/背光引脚驱动（策略见文件头；pin_bl == pin_pwr 时按同脚特例处理）
    local pwr_pin = params.pin_pwr
    local bl_pin  = params.pin_bl
    if bl_pin and bl_pin == pwr_pin then
        if params.ic_init then
            -- SPI 写 IC 寄存器必须先上电，背光只能随之点亮
            gpio.setup(pwr_pin, 1)
            gpio.set(pwr_pin, 1)
        else
            -- 纯 RGB 时序：整体延后到 backlight_on，输出低压住
            gpio.setup(bl_pin, 0)
        end
        pwr_pin = nil
        bl_pin  = nil
    end
    if pwr_pin then
        gpio.setup(pwr_pin, 1)
        gpio.set(pwr_pin, 1)
    end
    if bl_pin then
        -- 背光延后：输出低保持熄灭，等 backlight_on 点亮
        gpio.setup(bl_pin, 0)
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
        -- 引脚：pin_bl/pin_pwr 不透传（策略见文件头），pin_rst 由 display 内部做复位时序
        pin_rst   = params.pin_rst,
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
