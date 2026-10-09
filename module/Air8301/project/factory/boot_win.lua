--[[
@module  boot_win
@summary 开机画面（LOGO 启动页）—— 对齐工厂引擎 boot_ui + welcome_win 的启动范式
@version 1.1
@date    2026.10.08
@author  江访

@usage
界面：全屏深色底 + 居中 LOGO（引擎主机同款 /luadb/logo.png，128×128 原尺寸）
    + 产品名 + 版本号 + 底部启动指示点（循环点亮）。

停留时长：最短 MIN_SHOW_MS=1800ms（保证 LOGO 被看清）、兜底 MAX_WAIT_MS=5000ms。
收尾条件 = 「最短停留满足」且「初始化完成(BOOT_INIT_DONE)」，取两者中较晚者。

=== 启动时序（由 ui_main / prod_ui_main 的初始化协程驱动） ===

  lcd_drv.init()              LCD 硬件初始化（内含 lcd.clear，背光未开 → 用户不可见）
  lcd_drv.airui_init()        AirUI 引擎 + 字体 + 密度
  OPEN_BOOT_WIN(next_msg)     本页创建（全屏深色底 + LOGO），next_msg 指定进入的首页
  sys.wait(100)               等 LOGO 首帧刷上屏
  lcd_drv.backlight_on()      开背光 ← 用户第一眼看到的就是开机画面（而非黑屏/白屏）
  tp_drv.init()               触摸初始化
  BOOT_INIT_DONE              本页收尾 → publish(next_msg) 打开首页 → close 自己

=== 关键设计（与「引擎主机」开机画面一致的三条原则） ===

1) 「点亮屏幕」提到初始化链头：黑屏时长只剩固件启动 + display init 的固定开销，
   其余初始化（触摸 / 首页构建）与 LOGO 展示并行，不增加整机启动总时长。

2) 先画 LOGO 后开背光：避免用户看到 lcd.clear 的清屏过程与首帧黑屏。
   背光延迟量 BOOT_BACKLIGHT_DELAY_MS 即为此余量（首帧慢的屏可调大到 150~200）。

3) 收尾用「先开新页、再关自己」：打开首页后本页才 close，exwin 窗口栈全程非空，
   进入首页无白屏闪烁。

=== 可移植性说明（零资源依赖） ===

LOGO 资源：优先使用 /luadb/logo.png（128×128 原尺寸显示，源图 src/logo.png 即 128×128）；
      资源缺失时自动回退为绘制版标识（圆角方块 + "8301"），因此本页缺图不会报错、不会影响开机流程。
      若替换为其他尺寸的 LOGO，请同步调整 on_create 中的 lsz。颜色来源：底色用 theme.C.black
      （与引擎主机 welcome_win 的纯黑底一致），文字与指示点复用 ui_theme 令牌。

入口消息 DOCK 与首页消息名解耦：业务模式传 "OPEN_IDLE_WIN"，
产测模式传 "OPEN_PROD_IDLE_WIN"，本页不自带模式判断。
]]

local theme = require "ui_theme"

-- 开机画面最短停留：保证 LOGO 被用户看清，避免一闪而过
-- 参考引擎主机（factory_new welcome_win + hzv 视频）的品牌露出时长，此处取 1800ms。
-- 注意：调整本值时必须同步调整 ui_main / prod_ui_main 步骤7 的兜底等待（须 > 本值）
local MIN_SHOW_MS = 1800
-- 初始化兜底超时：初始化异常卡死时也能进入首页（不把用户留在启动页）
local MAX_WAIT_MS = 5000
-- 底部启动指示点的循环点亮周期
local DOT_PERIOD_MS = 320

local win_id = nil
local root                     -- 全屏根容器
local dots = {}                -- 启动指示点（3 个）
local dot_idx = 0              -- 当前点亮的点序号（1..3）
local dot_timer, min_timer, max_timer
local next_msg = "OPEN_IDLE_WIN"

local min_ok = false           -- 最短停留是否已满足
local boot_ok = false          -- 初始化是否已完成
local finished = false         -- 收尾闸门（只生效一次）

--[[
停掉本页全部定时器（收尾与销毁时调用，幂等）

@local
@function stop_timers
]]
local function stop_timers()
    if dot_timer then sys.timerStop(dot_timer) dot_timer = nil end
    if min_timer then sys.timerStop(min_timer) min_timer = nil end
    if max_timer then sys.timerStop(max_timer) max_timer = nil end
end

--[[
收尾：打开首页 → 关闭自己

顺序至关重要：先 publish 打开首页（首页创建并入栈），再关闭本页，
exwin 窗口栈全程非空，用户不会看到白屏。

@local
@function finish
@param string reason 收尾原因（仅日志用）
]]
local function finish(reason)
    if finished or not win_id then return end
    finished = true
    _G.__boot_finished = true
    stop_timers()
    log.info("boot_win", "开机画面结束(", reason, ")，进入", next_msg)
    sys.publish(next_msg)
    exwin.close(win_id)
end

--[[
入场闸门：最短停留与初始化完成同时满足才收尾

@local
@function try_finish
]]
local function try_finish()
    if min_ok and boot_ok then finish("就绪") end
end

--[[
初始化完成通知（ui_main / prod_ui_main 发布 BOOT_INIT_DONE）

@local
@function on_boot_init_done
]]
local function on_boot_init_done()
    boot_ok = true
    if max_timer then
        sys.timerStop(max_timer)
        max_timer = nil
    end
    try_finish()
end

--[[
启动指示点循环点亮（跑马灯效果，给出「正在启动」的动态反馈）

@local
@function tick_dots
]]
local function tick_dots()
    if #dots == 0 then return end
    dot_idx = dot_idx % #dots + 1
    for i = 1, #dots do
        dots[i]:set_color(i <= dot_idx and theme.C.amber or theme.C.stroke, 255)
    end
end

--[[
窗口创建回调：构建全屏开机画面

@local
@function on_create
]]
local function on_create()
    log.info("boot_win", "[UI-MARK] 开机画面 v1.1 已加载（LOGO 启动页，停留 1800ms）")
    finished = false
    min_ok = false
    boot_ok = false
    dot_idx = 0
    dots = {}

    local SW, SH = theme.SCREEN_W, theme.SCREEN_H

    -- ---- 全屏深色底 ----
    -- 显式挂到 airui.screen；个别 airui 版本无该常量时回退为 nil（airui 默认挂屏幕）
    root = theme.box(airui.screen, {
        x = 0, y = 0, w = SW, h = SH,
        color = theme.C.black,   -- 与引擎主机欢迎页一致：纯黑底衬托 LOGO
    })

    -- ---- LOGO：优先图片，缺失则绘制版标识 ----
    local lsz = 128
    local lx = math.floor((SW - lsz) / 2)
    local ly = 20

    local logo_path
    for _, p in ipairs({ "/luadb/logo.png", "/logo.png" }) do
        if io.exists(p) then logo_path = p break end
    end

    if logo_path then
        theme.image(root, { x = lx, y = ly, w = lsz, h = lsz, src = logo_path })
    else
        local logo_box = theme.box(root, {
            x = lx, y = ly, w = lsz, h = lsz,
            color = theme.C.panel,
            radius = theme.r("lg") + 6,
            border = theme.C.amber,
        })
        theme.label(logo_box, {
            x = 0, y = math.floor((lsz - (34 + 3)) / 2), w = lsz, h = 34 + 3,
            text = "8301", px_size = 34, color = theme.C.amber,
            align = airui.TEXT_ALIGN_CENTER,
        })
    end

    -- ---- 产品名 ----
    local title_y = ly + lsz + 10
    theme.label(root, {
        x = 0, y = title_y, w = SW, h = 18 + 3,
        text = "Air8301 出厂固件", px_size = 18, color = theme.C.t1,
        align = airui.TEXT_ALIGN_CENTER,
    })

    -- ---- 版本号（PROJECT / VERSION 由 main.lua 定义） ----
    theme.label(root, {
        x = 0, y = title_y + 23, w = SW, h = 16 + 3,
        text = "版本 " .. tostring(VERSION or ""), px_size = 16, color = theme.C.t3,
        align = airui.TEXT_ALIGN_CENTER,
    })

    -- ---- 底部启动指示：文字 + 3 个指示点 ----
    local hint_y = 214
    local txt_w, gap, dw, dgap = 80, 8, 8, 8
    local total = txt_w + gap + dw * 3 + dgap * 2
    local x0 = math.floor((SW - total) / 2)

    theme.label(root, {
        x = x0, y = hint_y, w = txt_w, h = 16 + 3,
        text = "正在启动", px_size = 16, color = theme.C.t2,
        align = airui.TEXT_ALIGN_CENTER,
    })

    local dx = x0 + txt_w + gap
    local dy = hint_y + math.floor((19 - dw) / 2)
    for i = 1, 3 do
        dots[i] = theme.dot(root, {
            x = dx + (i - 1) * (dw + dgap), y = dy, d = dw,
            color = theme.C.stroke,
        })
    end
    tick_dots()   -- 首帧立即点亮第 1 个点

    -- ---- 定时器 ----
    min_timer = sys.timerStart(function()
        min_timer = nil
        min_ok = true
        try_finish()
    end, MIN_SHOW_MS)

    max_timer = sys.timerStart(function()
        max_timer = nil
        log.warn("boot_win", "初始化未在", MAX_WAIT_MS, "ms 内完成，兜底进入首页")
        boot_ok = true
        try_finish()
    end, MAX_WAIT_MS)

    dot_timer = sys.timerLoopStart(tick_dots, DOT_PERIOD_MS)

    -- 粘性标记补查：初始化早于本页创建时（极小概率）不丢事件
    if _G.__boot_init_done then boot_ok = true end
    -- 延后一次尝试：此刻 exwin.open 尚未返回，win_id 还不可用
    sys.timerStart(try_finish, 10)
end

--[[
窗口销毁回调：释放组件与定时器

@local
@function on_destroy
]]
local function on_destroy()
    finished = true
    stop_timers()
    dots = {}
    if root then
        root:destroy()
        root = nil
    end
    win_id = nil
end

--[[
OPEN_BOOT_WIN 消息处理器

@local
@function open_handler
@param string msg 收尾后要打开的首页消息名（缺省 OPEN_IDLE_WIN）
]]
local function open_handler(msg)
    if msg then next_msg = msg end
    if win_id then return end
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_get_focus = function() end,
        on_lose_focus = function() end,
    })
end

sys.subscribe("OPEN_BOOT_WIN", open_handler)
sys.subscribe("BOOT_INIT_DONE", on_boot_init_done)
