-- 模块功能：u8g2 hzfont(矢量中文字体)PC 模拟器 demo
-- 触发条件：i2c_id == 21(对应 bsp/pc/ui/luat_u8g2_sdl2.c 中的 LUAT_PC_U8G2_EMU_ID)
-- 编译方式：build_windows_64bit_msvc_gui.bat (必须 GUI build, 否则不包含 hzfont)
-- 说明：演示 u8g2 在 hzfont 开启时, 用 DrawHzfontText 专门绘制 hzfont 字体数据
-- @module u8g2_hzfont
-- @author wendal
-- @release 2026.06.30

-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "u8g2_hzfont"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

--添加硬狗防止程序卡死
wdt.init(9000)--初始化watchdog设置为9s
sys.timerLoopStart(wdt.feed, 3000)--3s喂一次狗


-- 主流程
sys.taskInit(function()

    -- 1. 初始化 hzfont, 无参 = 使用内置 TTF(GUI build 已内置 MiSans GB2312)
    --    必须先于 u8g2.SetHzFont, 否则 hzfont 未 READY 会导致设置失败
    log.info("hzfont", "init")
    if not hzfont.init() then
        log.error("hzfont", "init failed, 请确认使用 GUI build (LUAT_USE_HZFONT)")
        os.exit(1)
    end
    hzfont.debug(false)

    -- SPI 屏幕引脚配置(仅占位,模拟器不会真的去拉 GPIO;真实硬件接法参考模块原理图)
    local spi_id, spi_res, spi_dc, spi_cs = 21, 0, 1, 2

    -- 初始化 SPI 显示屏(走 PC 模拟器,弹出 SDL2 窗口)
    log.info("init st7305_168x384 (PC emulator, spi_id=21, 168x384 1bpp full buffer, 竖屏 direction=0)")
    u8g2.begin({ic = "st7305_168x384", direction = 0, mode = "spi_hw_4pin", spi_id = spi_id, spi_res = spi_res, spi_dc = spi_dc, spi_cs = spi_cs})

    -- 3. 启用 hzfont(在当前 u8g2 上下文设置 is_hzfont_enabled=1)
    --    path 仅保存不用于加载, 传 nil 即可; size 范围 12~255
    u8g2.SetFontMode(1)
    u8g2.SetHzFont(nil, 12, 1)

    -- 测宽接口验证
    local w = u8g2.GetHzfontWidth("合宙", 12)
    log.info("hzfont", "GetHzfontWidth('合宙', 12) =", w)

    while true do
        -- 第一帧: 纯中文 + 中英混排, 字号 12
        u8g2.ClearBuffer()
        local n1 = u8g2.DrawHzfontText(0, 14, "合宙物联网", 12)
        local n2 = u8g2.DrawHzfontText(0, 30, "LuatOS中文", 12)
        u8g2.SendBuffer()
        log.info("u8g2 hzfont", "frame1 sent", "drawn:", n1, n2)
        sys.wait(2000)

        -- 第二帧: 字号 16, 演示不同字号
        u8g2.ClearBuffer()
        local n3 = u8g2.DrawHzfontText(0, 18, "矢量字体", 16)
        local n4 = u8g2.DrawHzfontText(0, 40, "16px测试", 16)
        u8g2.SendBuffer()
        log.info("u8g2 hzfont", "frame2 sent", "drawn:", n3, n4)
        sys.wait(2000)

        log.info("main", "u8g2 hzfont demo loop done")
    end
end)

-- 主循环, 必须加
sys.run()
