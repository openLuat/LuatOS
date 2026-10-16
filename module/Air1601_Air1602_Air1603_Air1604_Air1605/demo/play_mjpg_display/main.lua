--[[
@module  main
@summary EVB_Air1601_7inch 播放 fly_man_80.mjpg 测试（display 库 + AirUI）
@version 1.0
@date    2026.09.15
@usage
播放 /luadb/fly_man_80.mjpg，用 display 库初始化 RGB 屏(1024x600, HX8282)，
再交给 AirUI 的 airui.video 组件显示，居中 + 循环播放。
]]

PROJECT = "play_mjpg_display"
VERSION = "1.0.0"

-- 视频文件路径（放 luadb 分区）
local VIDEO = "/luadb/fly_man_80.mjpg"

-- LCD 尺寸
local LCD_W, LCD_H = 1024, 600

sys.taskInit(function()
    -- ===== 1. 用 display 库初始化 RGB 屏（HX8282 1024x600，四合一无需 SPI 初始化序列）=====
    -- 注意：AirUI 通过 luat_display_get_by_id(0) 取默认屏，这里必须显式 id=0
    local ok, err = display.init("custom", {
        id        = 0,
        interface = "rgb",
        w         = LCD_W,
        h         = LCD_H,
        -- HX8282 RGB 时序（取自 evb_1601_7i_v11.lua）
        hbp  = 140, hspw = 20, hfp = 160,
        vbp  = 20,  vspw = 3,  vfp = 12,
        pclk_hz = 50 * 1000 * 1000,
        pin_rst = 15,
        pin_pwr = 2,      -- GPIO2 同时控制背光+供电
    })
    if not ok then
        log.error("main", "display.init fail", err)
        return
    end
    log.info("main", "display.init ok")

    -- ===== 2. 读视频真实分辨率，用于居中 =====
    local vw, vh = 160, 160
    local p = videoplayer.open(VIDEO)
    if p then
        local info = videoplayer.info(p)
        if info then vw, vh = info.width, info.height end
        videoplayer.close(p)
    else
        log.warn("main", "can't open video, use 160x160")
    end
    local vx = math.max(0, math.floor((LCD_W - vw) / 2))
    local vy = math.max(0, math.floor((LCD_H - vh) / 2))

    -- ===== 3. 初始化 AirUI（全局可用，late-load，不需 require）=====
    if not airui.init(LCD_W, LCD_H) then
        log.error("main", "airui.init fail")
        return
    end
    log.info("main", "airui.init ok", LCD_W, LCD_H)

    -- ===== 4. 全屏黑色背景 + 居中视频组件 =====
    local bg = airui.container({ x = 0, y = 0, w = LCD_W, h = LCD_H, color = 0x000000 })
    local v = airui.video({
        parent = bg,
        x = vx, y = vy, w = vw, h = vh,
        src = VIDEO,
        format = "mjpg",
        decode_mode = "hw",   -- 硬件解码（CCM42xx imagedecoder）
        interval = 66,        -- 约15fps
        loop = true,          -- 循环播放
        auto_play = true,     -- 创建即播放
    })
    if not v then
        log.error("main", "airui.video create fail")
        return
    end

    log.info("main", "video playing", vw, "x", vh, "at", vx, vy)

    while true do
        sys.wait(1000)
        log.info("main", "mem", rtos.meminfo("sys"))
    end
end)

sys.run()