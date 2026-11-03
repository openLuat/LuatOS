--[[
@module  theme
@summary 益智乐园 - 设计令牌（配色 / 布局 / 字号 / 按钮样式 / 刷新预算）
@version 1.2
@date    2026.11.03

=== 这台 APP 是给谁做的 ===
给 6~10 岁孩子玩的七款益智小游戏 + 一个成绩排行榜，十寸屏、手指点、不认字也能玩：
颜色要亮、要分得清，形状要大、要按得中，反馈要快、要夸人。
所以整套视觉走"糖果色 + 奶油底"，不用深色科幻风：
  底色奶油黄（长时间看不刺眼，也不像黑板那么冷）
  卡片纯白 + 圆角 + 彩色描边（像贴纸，不是仪表盘）
  七款游戏各一个主题色，进游戏后顶栏色条、按钮、标题都跟着换
  所有文字用暖棕色，不用纯黑（纯黑压在浅底上太生硬）
数字与图标一律"高饱和色块 + 白字"，孩子在 1.5 米外也能一眼分清。

=== 坐标体系（1024x600）===
  顶栏 HUD   y   0 .. 58    标题 | 游戏名 + 玩法一句话 | 战绩两行
  舞台外框   x  12 .. 1012  y  62 .. 514   1000 x 452
  舞台内容   x  15 .. 1009  y  65 .. 511   994 x 446
  底部操作栏 y 522 .. 588    大厅 / 重玩 / 玩法 + 操作提示

=== 字体注意 ===
hzfont 里没有中间点（·）、度数（°）、乘号（×）、约等于（±/Ω/μ）这类符号，
用了会显示方框。界面文本只用 ASCII + 汉字 + 斜杠：
分隔用 "/"、时间写 "01:23"、百分号直接 "%"。
]]

local M = {}

-- ==================== 配色 ====================
local c = {
    -- 底与面：奶油底 + 纯白卡片，浅底浅得下去才衬得出彩色
    bg       = 0xFFF6E5,   -- 全屏底色（奶油黄）
    deep     = 0xFFFCF4,   -- 舞台底色（近白，暖）
    panel    = 0xFFFFFF,   -- 卡片 / 面板底
    panel_hl = 0xFFE9C9,   -- 未翻开格 / 面板高光
    tile     = 0xF6E5C8,   -- 棋盘空格
    line     = 0xF0DCC0,   -- 常规描边（浅）
    line2    = 0xE0C39B,   -- 亮描边 / 网格线
    dim2     = 0xAE9572,   -- 极弱文字 / 装饰
    dim      = 0x866E52,   -- 次要文字（比常规灰更暖，浅底上更清楚）
    txt      = 0x5A4630,   -- 主文字（暖棕，不用纯黑）
    ink      = 0xFFFFFF,   -- 亮色底上的文字色

    -- 七个主题色：糖果色系，饱和度够高才压得住奶油底
    cyan     = 0x2FC6DE,   -- 湖蓝（华容道）
    blue     = 0x5B8DEF,   -- 天蓝（水管工）
    violet   = 0x9B6BFF,   -- 葡萄紫（翻牌记忆）
    magenta  = 0xFF6FB5,   -- 泡泡粉（记忆序列）
    green    = 0x45C96B,   -- 草绿（扫雷）
    lime     = 0x9BDD3F,   -- 青柠
    amber    = 0xFFC53D,   -- 太阳黄（2048）
    orange   = 0xFF8A3D,   -- 蜜橘
    red      = 0xFF6B6B,   -- 珊瑚红
    teal     = 0x2FBFA0,   -- 薄荷绿（五子棋）

    -- 排行榜的金银铜：颁奖台那三种颜色，孩子一眼就知道哪个更厉害
    gold     = 0xFFC53D,
    silver   = 0xC3CBD6,
    bronze   = 0xD08A5A,
}
M.c = c

-- 七款游戏的主色（顺序与 ui_shell 的 PAGES 一致）
M.accents = { c.amber, c.cyan, c.violet, c.green, c.blue, c.magenta, c.teal }

-- ==================== 布局 ====================
M.screen = { w = 1024, h = 600 }
M.hud    = { h = 58 }
M.stage  = { x = 12, y = 62, w = 1000, h = 452 }
M.inner  = { x = 15, y = 65, w = 994, h = 446 }

M.bar    = { y = 522, h = 66 }
M.btn    = { x = 26, y = 532, w = 116, h = 46, gap = 10 }
M.bar_tip = { x = 400, y = 532, w = 590, h = 46 }   -- 底部右侧操作提示

-- 大厅卡片网格：4 列 x 2 行 = 8 张卡（7 款游戏 + 1 个排行榜入口）
-- 4*241 + 3*10 = 994 正好铺满内容区宽；2*218 + 10 = 446 正好铺满高，
-- 所以这块网格不需要任何居中偏移。
M.card = {
    cols = 4, rows = 2,
    w = 241, h = 218,
    gap = 10,
}

-- 榜单页（相对舞台内容区 994x446）
--   左侧 7 个游戏标签竖排：7*54 + 6*8 = 426，上下各留 10
--   右侧榜单卡：5 行 * 64 + 4 * 8 = 352，顶部 72 起
M.rank = {
    tab   = { x = 0, y = 10, w = 170, h = 54, gap = 8 },
    board = { x = 184, y = 0, w = 810, h = 446 },
    row   = { y = 72, h = 64, gap = 8 },
    badge = 36,    -- 名次徽章直径
}

-- 通用弹窗（相对舞台外框，1000x452）
M.overlay = {
    x = 0, y = 0, w = 1000, h = 452,
    px = 268, py = 78, pw = 464, ph = 296,
}

-- ==================== 字号 ====================
-- app_main.lua 按 font_sizes 逐个 airui.font_load，界面上用到的字号必须都在里面
M.font_sizes = { 11, 13, 16, 22, 26, 30, 48 }
M.f = {
    big   = 48,   -- 弹窗大标题
    val   = 30,   -- 棋盘数字
    title = 26,   -- 顶栏标题
    body  = 22,   -- 卡片标题 / 弹窗正文大号
    text  = 16,   -- 常规正文
    sub   = 13,   -- 说明文字
    mini  = 11,   -- 极弱标注
}

-- ==================== 按钮样式 ====================
-- 孩子的手指比大人粗、准头差：按钮统一 46px 高、圆角 14，颜色对比较强
M.style = {
    -- 主操作（蓝底白字）
    btn_main = {
        bg_color = 0x5B8DEF, bg_opa = 255, text_color = c.ink,
        radius = 14, border_width = 0, border_color = 0x5B8DEF,
        pressed_bg_color = 0x8FB6F5, pressed_text_color = c.ink,
    },
    -- 次操作（白底蓝字蓝边，像贴纸按钮）
    btn_ghost = {
        bg_color = c.panel, bg_opa = 255, text_color = 0x4A78D8,
        radius = 14, border_width = 2, border_color = 0x9FC0F2,
        pressed_bg_color = 0xE8F0FF, pressed_text_color = 0x2F5FBF,
    },
    -- 弹窗里的"继续 / 再玩一次"（绿底白字）
    btn_go = {
        bg_color = 0x45C96B, bg_opa = 255, text_color = c.ink,
        radius = 14, border_width = 0, border_color = 0x45C96B,
        pressed_bg_color = 0x86E09D, pressed_text_color = c.ink,
    },
}

-- ==================== 绘制用色（图元层复用，避免各游戏各写一份）====================
M.paint = {
    shadow   = 0xE7D2AE,   -- 卡片投影
    board    = 0xFFEFD6,   -- 棋盘底板
    board_ln = 0xE9CDA4,   -- 棋盘描边
    slot     = 0xF7E8CE,   -- 棋盘空格
    white    = 0xFFFFFF,
}

-- ==================== 刷新预算 ====================
M.perf = {
    frame_ms = 30,   -- 主循环节拍（30ms 避开 LVGL 33ms 刷新拍频）
    text_ms  = 200,  -- HUD 文字刷新 5Hz：set_text 会重排文本并产生脏区
}

-- ==================== 小工具 ====================
--[[秒数格式化成 mm:ss（超过一小时也按分钟累加）]]
function M.mmss(sec)
    sec = math.floor(sec or 0)
    if sec < 0 then sec = 0 end
    local m = math.floor(sec / 60)
    local s = sec % 60
    return string.format("%02d:%02d", m, s)
end

--[[点是否落在矩形内（左闭右开，避免相邻卡片在边界上同时命中）]]
function M.hit(px, py, x, y, w, h)
    return px >= x and px < x + w and py >= y and py < y + h
end

return M
