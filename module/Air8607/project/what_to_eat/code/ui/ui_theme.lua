--[[
@module  ui_theme
@summary 今天吃什么 - 设计令牌（配色 / 几何 / 字号 / 节奏）与三页转盘规格
@version 1.0
@date    2026.10.26

=== 设计取向 ===
温暖卡通（Warm Cartoon）：奶油底色 + 橙红主色 + 圆角白卡片 + 粗描边 + 糖果色扇区。
整屏像一张「可爱点餐海报」，靠色块与形状分层，不用阴影与渐变（LVGL 软件渲染，
阴影开销大且没有层次感），全部元素都是 AirUI 矢量的 container / label / shape。

=== 为什么整屏零图片 ===
真机图片缓存只有 1MB（components/airui/inc/luat_airui_conf.h 里
LUAT_USE_AIRUI_LUATOS 分支 LV_CACHE_DEF_SIZE = 1024*1024），一张 500x500 的
RGBA 盘面就接近 1MB，来回切页必然把缓存挤爆。所以盘面、灯泡、卡片全部现场画。

=== 为什么扇区用「胶囊」而不是 arc ===
airui.shape 的 arc 图元在软件渲染器里每个圆弧的绘制任务区是「整圆外接矩形」，
50 个扇区一次整盘重绘要跑 50 次 546x546 的角度掩码，真机会卡 0.3s 以上；而且
arc 是 2026-10 才加进 shape 的新图元，老固件未必有。改用 line 图元 + 圆头
（round_start/round_end）拼出来的「胶囊」：每个只栅格化自己覆盖的像素，
整盘约 13 万像素，并且只依赖 line/circle/rect 三个最老的图元。

=== 坐标体系（1024x600）===
  顶栏       y    0 .. 68    图标 + 标题 + 三个页签 + 页签指示条（绝对坐标）
  页面容器   y   68 .. 600   1024 x 532，三页各一层，靠 set_hidden 切换
  转盘       页面内圆心 (330, 270)  外盘半径 252  →  屏幕 y 86..590
  右侧面板   页面内 (648, 10) 368 x 514

  ⚠ 三个页面容器**不能盖住顶栏**：airui 的 container 保留了 LVGL 的 CLICKABLE 标志，
  一个没有回调的全屏透明容器会吃掉页签按钮的点击。所以页面层从 y=68 起，
  页面内坐标 = 屏幕坐标 - (0, 68)。

=== 字体注意 ===
hzfont 里没有长破折号（—）、摄氏度（℃）、中间点（·）这类符号，用了出方框。
app/foods.lua 会在加载时统一替换成兼容写法，界面文本本身只用 ASCII + 汉字。
]]

local M = {}

M.screen = { w = 1024, h = 600 }
M.topbar = { h = 68 }

-- ==================== 配色 ====================
M.c = {
    bg        = 0xFFF6E5,  -- 全屏奶油底
    bg_dot    = 0xFFE9C9,  -- 背景装饰圆
    bg_dot2   = 0xFFF1D6,  -- 背景装饰圆（更淡）
    plate     = 0xFFD79A,  -- 转盘盘体 / 外圈
    hub       = 0xFFFFFF,  -- 中心毂
    hub_ring  = 0xFFF1D6,  -- 中心毂外圈
    ink       = 0x3B3029,  -- 主文字
    sub       = 0x7A5C4A,  -- 次要文字
    mute      = 0x9A8B80,  -- 弱文字
    faint     = 0xC9BBAA,  -- 极弱文字 / 占位
    line      = 0xEADFCF,  -- 分隔线 / 卡片描边
    card      = 0xFFFFFF,  -- 卡片底
    tint      = 0xFFF8EC,  -- 卡片淡底
    cream     = 0xFFF1D6,  -- 提示条底
    accent    = 0xF2643C,  -- 主色（橙红）
    accent2   = 0xFF8A3D,  -- 主色亮
    yellow    = 0xFFE08A,  -- 点缀黄
    num       = 0x5C4130,  -- 扇区编号
    num_hot   = 0xD8410B,  -- 编号高亮
    white     = 0xFFFFFF,
    -- 三个页面的糖果色（两色交替）
    diet_a    = 0xB7E4C7, diet_b = 0x9BD8B0,
    diet_chip = 0xDFF5E6, diet_chip_t = 0x2F8F5B,
    out_a     = 0xFFD79A, out_b  = 0xFFC47A,
    out_chip  = 0xFFEEDD, out_chip_t = 0xC2622E,
    meat_a    = 0xFFC9A3, meat_b = 0xFFB088, meat_d = 0xC2622E,
    veg_a     = 0xC8E6A0, veg_b  = 0xB2D97F, veg_d  = 0x4F8A2B,
    soup_a    = 0xBFE3F2, soup_b = 0xA5D4E8, soup_d = 0x2F6F8F,
}

-- ==================== 字号 ====================
M.f = {
    mini  = 11,   -- 卡片右侧「做法」、页脚
    num   = 12,   -- 扇区编号
    small = 13,   -- 菜谱小标题 / 卡片类别
    body  = 15,   -- 正文
    recipe = 16,  -- 减脂餐菜谱正文（比 body 大一档，10 寸屏更好读）
    card  = 18,   -- 卡片菜名 / 页签
    mid   = 22,   -- 面板标题 / 中心按钮
    big   = 30,   -- 顶栏标题 / 减脂餐菜名
    huge  = 36,   -- 外卖菜名
}
-- app_main.lua 按这张表逐个 airui.font_load；漏载不会报错，只会渲染成方框或回退字形
M.font_sizes = { 11, 12, 13, 15, 16, 18, 22, 30, 36 }

-- ==================== 布局 ====================
-- 页面层（三页共用同一块，页面内坐标）
M.page = { x = 0, y = 68, w = 1024, h = 532 }

-- 右侧面板（页面内坐标）
M.panel = { x = 648, y = 10, w = 368, h = 514, pad = 22, radius = 26 }

-- 顶栏页签（绝对坐标）
M.tab = { w = 104, h = 42, gap = 10, y = 13 }
M.tab[1] = { x = 668, y = M.tab.y }
M.tab[2] = { x = 782, y = M.tab.y }
M.tab[3] = { x = 896, y = M.tab.y }
M.tab_indicator = { w = 44, h = 5, y = 60 }

-- ==================== 转盘几何（页面内坐标）====================
M.wheel = {
    cx = 330, cy = 270,
    r_plate = 252,     -- 盘体外沿
    r_hub   = 96,      -- 中心毂半径
    r_btn   = 76,      -- 中心圆形按钮半径
    bulbs   = 44,      -- 盘边小灯泡数量
    bulb_r  = 4,
    bulb_ring = 244,   -- 灯泡所在半径
    r_in    = 104,     -- 扇区带内沿
    r_out   = 234,     -- 扇区带外沿
    sweep_box = 156,   -- 扫光带小对象边长（只脏这一块）
    sweep_len = 130,   -- 扫光带长度（沿半径）
    frame_ms = 30,     -- 动画固定步长（Air1603 的 mcu.ticks() 约 20ms/tick，不能当 dt）
}

--[[
每个环（ring）的字段：
  count    扇区数
  r0, r1   扇区带内外半径
  style    "radial"：胶囊沿半径铺（扇区角小、带很厚时用）
           "tangent"：胶囊沿圆弧铺（扇区角大、带宽和弧长接近时用）
  w        胶囊宽度（tangent 时是带宽方向，radial 时是弦长方向）
  segs     tangent 时一个扇区拆成几段（扇区角越大拆得越多，减少弦与弧的偏差）
  num_r    编号所在半径
  num_font 编号字号
  num_w    编号文本框宽（居中文本，超了会换行）
  num_h    编号文本框高
]]
M.rings = {
    diet = {
        { count = 50, r0 = 104, r1 = 234, style = "radial", w = 19, segs = 1,
          num_r = 178, num_font = 12, num_w = 22, num_h = 15,
          colorA = M.c.diet_a, colorB = M.c.diet_b },
    },
    out = {
        { count = 50, r0 = 104, r1 = 234, style = "radial", w = 19, segs = 1,
          num_r = 178, num_font = 12, num_w = 22, num_h = 15,
          colorA = M.c.out_a, colorB = M.c.out_b },
    },
    home = {
        -- 外环：荤菜 40
        { count = 40, r0 = 186, r1 = 234, style = "tangent", w = 42, segs = 1,
          num_r = 209, num_font = 12, num_w = 26, num_h = 15,
          colorA = M.c.meat_a, colorB = M.c.meat_b },
        -- 中环：素菜 30
        { count = 30, r0 = 138, r1 = 186, style = "tangent", w = 42, segs = 1,
          num_r = 161, num_font = 12, num_w = 26, num_h = 15,
          colorA = M.c.veg_a, colorB = M.c.veg_b },
        -- 内环：汤 10（扇区角 36 度，一段弦偏差 6px，拆两段后约 1.5px）
        { count = 10, r0 = 104, r1 = 138, style = "tangent", w = 28, segs = 2,
          num_r = 121, num_font = 11, num_w = 24, num_h = 14,
          colorA = M.c.soup_a, colorB = M.c.soup_b },
    },
}

-- ==================== 抽签节奏 ====================
M.spin = {
    single_ms = 3200,   -- 单抽时长（减脂餐 / 外卖）
    single_turns = 5,   -- 单抽圈数
    home_ms = 850,      -- 家常菜每次停靠时长
    home_turns = 2,     -- 家常菜每次停靠圈数（连停 5 次，共 10 圈）
    home_hold = 420,    -- 家常菜两次停靠之间的停顿
}

return M
