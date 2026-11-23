--[[
  app_config.lua  硬件参数 / 双色板 / 字号 / 布局常量
  Air8607 + 10.1 寸 1024x600 RGB + GT911

  === 双主题 ===
  日间「米白 + 墨青」：docs/美容仪UI效果稿.html
  夜间「深蓝科技」  ：docs/美容仪UI深蓝科技稿.html
  两稿版式逐像素一致，只换色彩系统，所以切主题只覆盖色板，不动布局。

  ⚠ C 必须是「同一张表原地覆盖」（见 M.use_theme）：
    各 ui 模块顶部 `local C = cfg.C` 捕获的是表引用，换成新表它们就看不见了。

  === 为什么强调色要拆成 fill / glow ===
  日间只有一个重色（墨青），同一个值既当按钮底又当细线条都没问题；
  夜间不行 —— 深蓝稿的 #4C8DFF 压白字只有 3.1:1，当按钮底会糊；
  而 #1D4ED8 当 1px 线条在 #070C16 上又暗得看不见。所以拆成两个角色：

    fill     实心填充（按钮底 / 档位条 / 进度段 / 页码长条）  夜间 #1D4ED8，白字 7.5:1
    glow     细线（卡片描边 / 品牌圆环 / 状态点 / 顶栏竖条）  夜间 #4C8DFF，5.9:1
    on_fill  压 fill 底的文字与图标                          夜间 #FFFFFF
    win      暗色展示窗内沿（产品图四周的暖白）               夜间 #F4F1EC

  === 色值映射 vs 令牌名（M.map 的坑） ===
  ui_widget.repaint 默认拿「旧色值 → 新色值」的 map 重涂。如果日间下
  fill 与 glow 取同一个值，map 里一个键只能有一个目标色，两个角色必然串味。
  解决办法：fill/glow/on_fill/win 以及 card/bg 这类「多语义同值」的令牌，
  创建控件时直接传**令牌名**（color = "glow"），走 M.C[token] 取值，
  完全不进 map。只有 ink/ink2/ink3/line/line2 这些值唯一的才走色值映射。

  轮廓令牌只用 line2（F6）：日间 line 与 bg 对比度 1.19:1，真机上看不出卡片边界；
  夜里差距更小，所以夜间 line2 提到 #28405F。
]]

local M = {}

-- ======================= 色板 =======================
-- 两套的键必须完全一致（use_theme 按同名键覆盖）
M.PALETTE = {
  day = {
    bg      = 0xF6F3EE,   -- 页面底（米白）
    card    = 0xFFFFFF,   -- 卡片底
    ink     = 0x1F1D1A,   -- 主文字
    ink2    = 0x57534C,   -- 次级文字
    ink3    = 0x8C857A,   -- 辅助文字
    line    = 0xE6E1D8,   -- 分隔线（不可圈块）
    line2   = 0xCFC8BC,   -- 块轮廓（1.44:1，唯一合规描边）
    fill    = 0x2C6E63,   -- 实心填充（墨青）
    glow    = 0x2C6E63,   -- 细线强调（日间与 fill 同色，靠令牌名区分）
    on_fill = 0xFFFFFF,   -- 压 fill 底的文字/图标
    win     = 0xF6F4EF,   -- 展示窗内沿（日间被图片盖住，取 bg 近似值）
  },
  night = {
    -- 取 docs/美容仪UI深蓝科技稿.html 的 :root，不凭记忆改
    bg      = 0x070C16,   -- --bg
    card    = 0x0C1626,   -- --panel
    ink     = 0xE6EFFC,   -- --ink    相对 bg 16.1:1
    ink2    = 0xA9BDD6,   -- --ink2    9.7:1
    ink3    = 0x7A8FA8,   -- --ink3    5.8:1
    line    = 0x17263C,   -- --line（纯分隔）
    line2   = 0x28405F,   -- --line2   1.9:1，暗底要更硬的轮廓
    fill    = 0x1D4ED8,   -- --btn     白字 7.5:1
    glow    = 0x4C8DFF,   -- --blue    5.9:1，细线在深底才够亮
    on_fill = 0xFFFFFF,   -- 白字压 #1D4ED8
    win     = 0xF4F1EC,   -- --win     产品图底色的暖白
  },
}

M.THEMES = { "day", "night" }
M.THEME_NAME = { day = "日间", night = "夜间" }

-- 当前生效色板：**始终是同一张表**，只改里面的值
M.C = {}
M.theme = "day"
-- 旧色值 → 新色值（只用于没传令牌名的控件）
M.map = {}

-- ======================= 主题切换 =======================
--- 原地覆盖色板并重建映射表。调用方随后应执行 ui_widget.repaint()。
--  @param name "day" | "night"
function M.use_theme(name)
  local pal = M.PALETTE[name]
  if not pal then
    log.warn("cfg", "未知主题", tostring(name))
    return false
  end

  -- 先记下旧值（首次调用时 M.C 是空表，old 全为 nil，map 为空，此时还没建控件）
  local old = {}
  for k, v in pairs(M.C) do old[k] = v end

  for k, v in pairs(pal) do M.C[k] = v end
  M.theme = name

  local map = {}
  for k, v in pairs(pal) do
    local o = old[k]
    -- 只映射「值唯一」的数值令牌；令牌名分支不查这张表
    if type(o) == "number" and type(v) == "number" then map[o] = v end
  end
  M.map = map
  return true
end

--- 另一个主题名
function M.other(name)
  return (name == "night") and "day" or "night"
end

M.use_theme("day")

-- ======================= 图片 =======================
-- 主题只用一套图：夜间不染色、不重出，改由 ui_carousel 的暖白垫层 + 遮边条
-- 表达「深框亮窗」。所以这里没有按主题拼前缀，别再加速度版目录。
M.IMG_W, M.IMG_H = 420, 280

function M.img_src(key)
  return "/luadb/mode_" .. tostring(key) .. ".png"
end

-- ======================= 暗色展示窗几何 =======================
-- 深蓝稿 .main{--pad:16px} / .side{--pad:10px}，窗口内 object-fit:contain。
-- 真机不做 fit 切换（会重置 pivot 让缩放往右下漂，见 ui_widget.image_raw），
-- 改为：暖白垫层铺满窗口 + 图片按基准 zoom 缩到窗口内 + 四周遮边条盖住外框。
M.WIN = {
  main = {
    pad = 16,              -- 相框厚度
    -- 窗口 386x230 内 contain 420x280 → 按高缩到 230，图 345x230
    zoom = 210,
  },
  side = {
    pad = 10,
    -- 窗口 212x186 内 contain → 按宽缩到 212，图 212x141
    zoom = 129,
    opacity = 140,         -- 深蓝稿 .side{opacity:.55}，只是变暗不改色相
  },
}

-- ======================= 硬件 =======================
M.HW = {
  screen = {
    w = 1024, h = 600,
    panel_w = 1024, panel_h = 600,
    -- 时序对齐 Air8607 出厂固件 eng_8607_10i_v0.lua
    hbp = 140, hspw = 20, hfp = 160,
    vbp = 20,  vspw = 3,  vfp = 12,
    bus_speed = 50000000,
    pin_rst = 15,
    pin_pwr = 15,
    pwm_ch  = 3,
    pwm_freq = 1000,
  },
  tp = {
    ic = "gt911", i2c_id = 1,
    pin_rst = 14, pin_int = 51, int_type = "falling",
  },
}

-- ======================= 节奏 =======================
M.ANIM = {
  frame_ms = 33,     -- 主循环节拍（约 30fps）
  -- 切换微缩动画：6 帧 × 33ms ≈ 200ms。帧数必须是整数，
  -- 且缩放曲线在首末帧必须落在圆整值上，否则末帧残留半像素抖动。
  zoom_frames = 6,
  zoom_in = 274,     -- 入场缩放（相对基准 256 的 107%）；夜间按比例折算
  tick_ms = 1000,    -- 倒计时 1Hz
  clk_ms  = 10000,   -- 时钟 10s 刷一次（分钟级变化够了）
}

-- ======================= 字号 =======================
-- hzfont 真实行高 = 字号 + 3；中文最小 16（F2）。
M.SIZES = { 16, 18, 28 }

-- ======================= 布局（设计画布 = 实机 1024x600） =======================
M.LAYOUT = {
  pad = 48, content_w = 928,

  top_h = 64,

  ov_y = 78,  ov_h = 104, ov_gap = 20, ov_w = 296,   -- 3×296 + 2×20 = 928

  car_y = 194, car_h = 264,
  side_w = 234, side_h = 208, side_top = 28,         -- 侧卡比焦点卡矮 56，垂直居中
  main_w = 420, main_h = 264,
  main_x = 254,  side_r_x = 694,                     -- 相对轮播容器：234+20 / 694+...

  tray_y = 470, tray_h = 104,

  -- 顶栏右侧三件（右边界 = 1024 - pad = 976，件间距 16，单位 px）
  -- 旧布局里时钟 923..976 压在电量胶囊 888..976 上，这轮按宽度实算重排
  theme_w = 72, theme_h = 28, theme_y = 18, theme_x = 731,   -- 731..803
  batt_w = 88, batt_h = 28, batt_x = 819, batt_y = 18,       -- 819..907
  clock_y = 21,                                              -- 923..976
}

return M
