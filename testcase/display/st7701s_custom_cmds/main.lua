PROJECT = "st7701s_custom_cmds"
VERSION = "1.0.0"
local sys = require("sys")

-- ============================================================================
-- 测试目标：
--   按 custom 面板策略初始化一块 "SPI 写命令 + RGB 显示" 的屏幕。
--   参数取自 luat_display_panel_rgb_st7701s.c，重点验证 Lua 侧 custom_cmds
--   自定义初始化命令序列 + RGB 时序参数是否完整生效。
--
--   对照关系（st7701s.c -> Lua custom 配置）：
--     timing   -> w/h + hspw/hbp/hfp/vspw/vbp/vfp + pclk_hz + 极性
--     panel_init 里每条 panel_spi_send_seq -> custom_cmds 里一行 {cmd, data..., delay=ms}
-- ============================================================================

-- 引脚配置（参照 testcase/airui/airui_basic/scripts/main.lua 的 st7701s 接线）：
-- 初始化寄存器的命令走 SPI（scl/sdi/cs/rst），显示通道走 RGB。
local PIN = {
    scl = 23,   -- SPI 时钟引脚（初始化通信）
    sdi = 2,    -- SPI 数据引脚
    cs  = 22,   -- SPI 片选引脚
    rst = 15,   -- 复位引脚
    dc  = -1,   -- SPI 数据/命令（示例未用到，按需填）
    bl  = -1,   -- 背光（示例用 pwm 通道3 从代码开关，不占 pin_bl）
}

-- st7701s 的 RGB 时序参数（来自 st7701s_timing）
local TIMING = {
    w = 480, h = 854,
    hspw = 10, hbp = 30, hfp = 30,   -- 水平：脉宽/后廊/前廊
    vspw = 2,  vbp = 16, vfp = 8,    -- 垂直：脉宽/后廊/前廊
    pclk_hz = 30 * 1000 * 1000,      -- 像素时钟 30MHz
    -- 极性：st7701s_timing.flags = HSYNC_LOW | VSYNC_LOW（0=低有效，1=高有效）
    -- pclk_polarity 参照 airui_basic 真机取 1（1=高电平/上升沿采样）
    hs_polarity    = 0,
    vs_polarity    = 0,
    pclk_polarity  = 1,
}

-- ============================================================================
-- custom_cmds：完全复刻 st7701s panel_init() 的初始化命令序列。
-- 每行一条命令：第 1 个元素是命令字节，后续是数据字节，delay=ms 为该命令发送后的延时。
-- delay 对应源码里的 luat_rtos_task_sleep()。
-- ============================================================================
local INIT_CMDS = {
    {0xFF, 0x77, 0x01, 0x00, 0x00, 0x13},                      -- 进入厂商命令页
    {0xEF, 0x08},
    {0xFF, 0x77, 0x01, 0x00, 0x00, 0x10},                      -- 切换页面
    {0xC0, 0xE9, 0x03},
    {0xC1, 0x11, 0x02},
    {0xC2, 0x01, 0x08},
    {0xCC, 0x18},
    {0xB0, 0x00, 0x0D, 0x14, 0x0D, 0x10, 0x05, 0x02, 0x08, 0x08, 0x1E, 0x05, 0x13, 0x11, 0xA3, 0x29, 0x18},  -- GIP 1
    {0xB1, 0x00, 0x0C, 0x14, 0x0C, 0x10, 0x05, 0x03, 0x08, 0x07, 0x20, 0x05, 0x13, 0x11, 0xA4, 0x29, 0x18},  -- GIP 2
    {0xFF, 0x77, 0x01, 0x00, 0x00, 0x11},                      -- 切换页面
    {0xB0, 0x6C},
    {0xB1, 0x43},
    {0xB2, 0x87},
    {0xB3, 0x80},
    {0xB5, 0x47},
    {0xB7, 0x85},
    {0xB8, 0x20},
    {0xB9, 0x10},
    {0xC1, 0x78},
    {0xC2, 0x78},
    {0xD0, 0x88, delay = 100},                                 -- 对应源码第2处 sleep(100)
    {0xE0, 0x00, 0x00, 0x02},
    {0xE1, 0x08, 0x00, 0x0A, 0x00, 0x07, 0x00, 0x09, 0x00, 0x00, 0x33, 0x33},
    {0xE2, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00},
    {0xE3, 0x00, 0x00, 0x33, 0x33},
    {0xE4, 0x44, 0x44},
    {0xE5, 0x0E, 0x60, 0xA0, 0xA0, 0x10, 0x60, 0xA0, 0xA0, 0x0A, 0x60, 0xA0, 0xA0, 0x0C, 0x60, 0xA0, 0xA0},
    {0xE6, 0x00, 0x00, 0x33, 0x33},
    {0xE7, 0x44, 0x44},
    {0xE8, 0x0D, 0x60, 0xA0, 0xA0, 0x0F, 0x60, 0xA0, 0xA0, 0x09, 0x60, 0xA0, 0xA0, 0x0B, 0x60, 0xA0, 0xA0},
    {0xEB, 0x02, 0x01, 0xE4, 0xE4, 0x44, 0x00, 0x40},
    {0xEC, 0x02, 0x01},
    {0xED, 0xAB, 0x89, 0x76, 0x54, 0x01, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x10, 0x45, 0x67, 0x98, 0xBA},
    {0xEF, 0x08, 0x08, 0x08, 0x45, 0x3F, 0x54},
    {0xFF, 0x77, 0x01, 0x00, 0x00, 0x13},                      -- 切回厂商命令页
    {0xE8, 0x00, 0x0E},
    {0xFF, 0x77, 0x01, 0x00, 0x00, 0x00},                      -- 回到正常页
    {0x11, delay = 120},                                       -- 退出睡眠，对应源码 sleep(120)
    {0xFF, 0x77, 0x01, 0x00, 0x00, 0x13},
    {0xE8, 0x00, 0x0C, delay = 10},                            -- 对应源码 sleep(10)
    {0xE8, 0x00, 0x00},
    {0xFF, 0x77, 0x01, 0x00, 0x00, 0x00},
    {0x29},                                                    -- 开显示
    {0x3A, 0x77},                                              -- 像素格式 RGB888
    {0x36, 0x08, delay = 20},                                  -- MADCTL 旋转，对应源码 sleep(20)
}

sys.taskInit(function()
    log.info("st7701s_custom", "lua_vm_ready")

    -- 走 custom 面板策略，传 st7701s 的时序 + 自定义命令序列
    local ok, err = display.init("custom", {
        interface   = "rgb",
        w           = TIMING.w,
        h           = TIMING.h,
        crop_w      = TIMING.w,
        crop_h      = TIMING.h,

        hspw        = TIMING.hspw,
        hbp         = TIMING.hbp,
        hfp         = TIMING.hfp,
        vspw        = TIMING.vspw,
        vbp         = TIMING.vbp,
        vfp         = TIMING.vfp,
        pclk_hz     = TIMING.pclk_hz,

        hs_polarity    = TIMING.hs_polarity,   -- 0 = 低有效
        vs_polarity    = TIMING.vs_polarity,   -- 0 = 低有效
        pclk_polarity  = TIMING.pclk_polarity, -- 1 = 上升沿采样

        -- SPI 引脚（st7701s 命令走 SPI）
        pin_rst     = PIN.rst,
        pin_cs      = PIN.cs,
        pin_scl     = PIN.scl,
        pin_sdi     = PIN.sdi,
        pin_dc      = PIN.dc,
        pin_bl      = PIN.bl,

        -- 自定义初始化命令序列（验证重点）
        custom_cmds = INIT_CMDS,
    })

    if not ok then
        log.error("st7701s_custom", "display.init failed", err or "unknown")
        return
    end
    log.info("st7701s_custom", "display.init ok")

    -- 背光：PWM 通道3, 1kHz, 占空比100%（参照 airui_basic）
    local ok_bl = pwm.open(3, 1000, 100)
    log.info("st7701s_custom", "pwm backlight", ok_bl)

    local w, h = display.getSize()
    log.info("st7701s_custom", "panel_size", "w", w, "h", h)

    local fb_addr, fb_size, fb_count = display.getFbInfo()
    log.info("st7701s_custom", "fb_info",
        "addr", fb_addr and tostring(fb_addr) or "nil",
        "size", fb_size or 0,
        "count", fb_count or 0)

    -- 循环红绿蓝填充，确认显示链路工作
    -- 注意：STM32N6 为「可见双缓冲」，fill 写 buff_draw，
    --       必须 flush 发布并 swap 后才上屏。
    local colors = {
        {"red",   0xF800},
        {"green", 0x07E0},
        {"blue",  0x001F},
    }
    while true do
        for _, c in ipairs(colors) do
            log.info("st7701s_custom", "fill_" .. c[1])
            display.fill(0, 0, w - 1, h - 1, c[2])
            display.flush()        -- 发布脏帧并双缓冲 swap
            sys.wait(500)
        end
    end
end)

sys.run()
