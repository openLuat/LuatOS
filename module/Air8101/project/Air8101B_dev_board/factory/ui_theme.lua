--[[
@module  ui_theme
@summary 界面主题：配色 / 字号 / 尺寸 / 缩放（全工程唯一来源）
@version 2.0
@date    2026.10.16
@usage
    local T = require "ui_theme"
    T.COLOR.PRIMARY        -- 颜色（24 位 RGB，0xRRGGBB）
    T.FONT.TITLE           -- 字号（已按屏幕缩放）
    T.GAP.M                -- 间距（设计值，组件内部自动换算）
    T.SCREEN.DW / DH       -- 设计基准宽高：页面布局坐标一律按它写
    T.px(56)               -- 设计像素 → 当前屏实际像素

多屏自适应（5 / 7 / 9 / 10 寸）
1. 设计基准固定 800×480，所有页面按这个坐标系写布局；
2. 实际屏（如 1024×600）用 SCALE = min(W/800, H/480) 统一放大（≈1.25），
   字号、间距、圆角、坐标全都跟着放大，页面代码不用为每种屏改一遍；
3. 尺寸来源：优先内核 lcd.getSize()（LCD 初始化后才是真值），其次 config 的 hw.lcd.w/h，
   最后兜底 800×480；ui_main 在 airui.init 之后还会调 T.setup(W, H) 同步一次真值；
4. 放大后的内容区（CW×CH）在整屏里**居中**（偏移 OX/OY）：屏幕宽高比和 800:480 不一致时，
   多出来的那条边由根容器背景色铺满（视觉上仍是全屏，不是黑边）；
5. 只有根容器用"真实像素"——ui_kit.page / ui_welcome 用 S.W/S.H 铺满整屏、
   用 S.OX/S.OY + S.CW/S.CH 摆内容区；业务页面一律只读 S.DW/S.DH（设计坐标）。

配色：清爽浅色 + 品牌蓝（浅灰底 + 白卡 + 圆角 + 柔和分隔）。
注意颜色是 24 位 RGB，别和 drv_lcd 里那套 RGB565（16 位）混用。
]]

local M = {}

local hw      = (_G.project_config or {}).hw or {}
local lcd_cfg = hw.lcd or {}     -- 注意：局部变量别叫 lcd，会遮蔽内核 lcd 库

-- 设计基准（页面布局坐标系）：所有页面按这个坐标系写
local DW, DH = 800, 480

-- 字号设计值（实际值由 recalc 按屏幕缩放，最小 12 保证可读）
local FONT_BASE = {
    XL     = 64,   -- 超大数值（温湿度等主读数）
    HUGE   = 40,
    BIG    = 28,
    TITLE  = 22,
    NORMAL = 20,
    SMALL  = 16,
    TINY   = 14,
}

local function probe_size()
    local ok, gw, gh = pcall(function() return lcd.getSize() end)
    if ok then
        gw, gh = tonumber(gw), tonumber(gh)
        if gw and gh and gw > 0 and gh > 0 then return gw, gh end
    end
    return tonumber(lcd_cfg.w) or DW, tonumber(lcd_cfg.h) or DH
end

local W, H = probe_size()

-- 内容区（设计基准 × scale）实际像素 + 在整屏里的居中偏移；recalc 里重算
local scale, CW, CH, OX, OY = 1, DW, DH, 0, 0

M.SCREEN = {
    W  = W,  H  = H,        -- 实际分辨率（整屏：根容器 / 驱动层用）
    DW = DW, DH = DH,       -- 设计基准（页面布局坐标一律按它算）
    CW = CW, CH = CH,       -- 内容区实际像素（= 设计基准 × SCALE）
    OX = OX, OY = OY,       -- 内容区居中偏移（相对整屏左上角）
    SCALE = scale,
    TITLE_H = 56,           -- 标题栏高度（设计值）
}

M.FONT = {}

function M.px(v)
    return math.floor(v * scale + 0.5)
end

local function recalc()
    scale = math.min(W / DW, H / DH)
    if scale <= 0 then scale = 1 end

    CW = math.floor(DW * scale + 0.5)
    CH = math.floor(DH * scale + 0.5)
    OX = math.floor((W - CW) / 2)
    OY = math.floor((H - CH) / 2)

    local S = M.SCREEN
    S.W, S.H, S.SCALE = W, H, scale
    S.CW, S.CH, S.OX, S.OY = CW, CH, OX, OY

    for k, v in pairs(FONT_BASE) do
        local f = math.floor(v * scale + 0.5)
        if f < 12 then f = 12 end
        M.FONT[k] = f
    end
end

recalc()

--- LCD 初始化完再同步一次内核真值（ui_main 在 airui.init 之后调用）；w/h 非法时忽略
function M.setup(w, h)
    w, h = tonumber(w), tonumber(h)
    if w and w > 0 then W = w end
    if h and h > 0 then H = h end
    recalc()
    log.info("ui_theme", "屏幕", W .. "×" .. H, "内容区", CW .. "×" .. CH,
        "缩放", string.format("%.3f", scale), "居中偏移", OX .. "," .. OY)
    return M.SCREEN
end

M.COLOR = {
    -- 品牌色
    PRIMARY       = 0x2F6FED,   -- 品牌蓝（标题栏、主按钮）
    PRIMARY_LIGHT = 0x5B8DF8,   -- 浅一档（空气质量等级 2 用）
    PRIMARY_SOFT  = 0xE8F0FE,   -- 浅蓝底（图标块、选中态背景）

    -- 中性
    BG            = 0xF4F6FA,   -- 页面背景（浅灰）
    CARD          = 0xFFFFFF,   -- 卡片
    BORDER        = 0xE6EAF0,   -- 分隔线 / 卡片描边
    TOAST         = 0x2B3440,   -- 提示条
    DISABLED      = 0xC3CBD6,

    -- 文字
    TEXT          = 0x1F2733,
    TEXT_SUB      = 0x55606D,
    TEXT_WEAK     = 0x93A0AD,
    TEXT_ON_DARK  = 0xFFFFFF,

    -- 语义色
    OK            = 0x22C55E,
    WARN          = 0xF59E0B,
    DANGER        = 0xEF4444,

    -- 桌面图标配色（一屏多色，别太跳）
    ICON_BLUE     = 0x3B82F6,
    ICON_TEAL     = 0x14B8A6,
    ICON_GREEN    = 0x22C55E,
    ICON_ORANGE   = 0xF59E0B,
    ICON_CYAN     = 0x06B6D4,
    ICON_SLATE    = 0x64748B,
    ICON_RED      = 0xEF4444,
}

-- 字号：M.FONT.* 已在上面的 recalc() 里按屏幕缩放生成（最小 12），这里不再重复计算

-- 间距（设计值，组件内部 px() 换算）
M.GAP = {
    XS = 6,
    S  = 10,
    M  = 20,
    L  = 40,
}

-- 圆角（设计值）
M.RADIUS = {
    S = 6,
    M = 12,
    L = 20,
}

return M
