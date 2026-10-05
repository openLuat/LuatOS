--[[
@module  welcome_win
@summary 开机欢迎页 —— 黑底 + 静态 logo，初始化完成后直接进入桌面
@version 5.0
@date    2026.10.05
@author  江访
@usage
订阅: OPEN_WELCOME_WIN  → 创建欢迎页（黑底 + logo 图）
订阅: BOOT_INIT_DONE    → 初始化完成，条件满足后收尾入场
发布: OPEN_IDLE_WIN     → 收尾后发布，触发桌面窗口

=== 状态机 ===

  LOGO 阶段（on_create）：
    黑底 + 居中 logo（/luadb/logo.png，128×128 1:1）。两个条件都满足才入场：
      1. 最短停留 BOOT_LOGO_MIN_MS 展满（防止初始化过快 logo 一闪而过）；
      2. BOOT_INIT_DONE 到达（或 BOOT_LOGO_MAX_WAIT_MS 兜底超时，防初始化卡死）。
    两个条件哪条后到都由 try_enter 触发收尾，无需关心先后顺序。

  开机动画已下线（2026-10-05）：欢迎页只展示 logo，不播放 MP4/HZV ——
  相应的视频分流（mp4_takeover / airui.video）、素材常量与容器探测一并移除，
  播放能力集中在桌面播放器（idle_win + mp4_loop / video_util）。

  收尾只有一条路径 finish()：finished 标志保证 OPEN_IDLE_WIN 只发布一次 ——
  重复 publish 会让 exwin 重复创建桌面。

LOGO 阶段零主题依赖（黑底用字面量 0x000000，不 require ui_theme），
使 welcome_win 可被 boot_ui 最早加载；logo 资源缺失时只显示黑底，流程不中断。
]]

local LOGO_SIZE = 128
-- logo 最短停留：防止初始化过快导致 logo 一闪而过
local BOOT_LOGO_MIN_MS = 500
-- logo 兜底：初始化卡死（如某模块 require 挂起）也强制入场，防止永久停在 logo
local BOOT_LOGO_MAX_WAIT_MS = 3000

local window_id = nil
local bg_shape
local logo_img

-- finished 是「只走一次」的闸门：进入桌面这件事必须只发生一次
local finished = false

--[[入场条件：最短停留展满(min_ok) 且 初始化完成(boot_ok) 才进桌面。
boot_ok 有两条来路：BOOT_INIT_DONE 事件、logo 兜底超时；粘性标记
_G.__boot_init_done 供 on_create 补查（防事件早于订阅丢失）。]]
local min_ok = false
local boot_ok = false
local min_timer = nil
local logo_wait_timer = nil

--[[收尾：进入桌面（条件满足 / 兜底超时共用，只生效一次）

@param reason string 仅用于日志，标明是哪条路径先到]]
local function finish(reason)
    if finished or not window_id then return end
    finished = true

    if min_timer then
        sys.timerStop(min_timer)
        min_timer = nil
    end
    if logo_wait_timer then
        sys.timerStop(logo_wait_timer)
        logo_wait_timer = nil
    end

    log.info("welcome_win", "开机 logo 结束(", reason, ")，进入桌面")
    sys.publish("OPEN_IDLE_WIN")
    exwin.close(window_id)
end

--[[入场闸门：min_ok 与 boot_ok 同时满足才收尾（哪条后到都由它触发，只走一次）]]
local function try_enter()
    if not (min_ok and boot_ok) then return end
    if finished or not window_id then return end
    finish("就绪")
end

--[[初始化完成（boot_ui 在分批加载完业务与 UI 模块、主题恢复后发布）

只置位并尝试入场；窗口尚未创建时 try_enter 会被 window_id 挡住，
入场时机由 on_create 查粘性标记 _G.__boot_init_done 补上（双保险）。]]
local function on_boot_init_done()
    boot_ok = true
    if logo_wait_timer then
        sys.timerStop(logo_wait_timer)
        logo_wait_timer = nil
    end
    try_enter()
end

local function on_create()
    finished = false
    min_ok = false
    boot_ok = false

    -- 黑色全屏背景（0x000000 字面量：零主题依赖，可被 boot_ui 最早加载）
    bg_shape = airui.shape({
        x = 0, y = 0, w = screen_w, h = screen_h,
        items = {
            { type = "rect", x = 0, y = 0, w = screen_w, h = screen_h,
              fill = true, fill_color = 0x000000, color = 0x000000 },
        },
    })

    -- logo 资源落点容错（/luadb/ 或根目录）；缺失只显示黑底，流程不中断
    local logo_path = nil
    for _, p in ipairs({ "/luadb/logo.png", "/logo.png" }) do
        if io.exists(p) then
            logo_path = p
            break
        end
    end
    if logo_path then
        -- 128×128 居中 1:1 显示，不缩放
        logo_img = airui.image({
            x = math.floor((screen_w - LOGO_SIZE) / 2),
            y = math.floor((screen_h - LOGO_SIZE) / 2),
            w = LOGO_SIZE, h = LOGO_SIZE,
            src = logo_path,
        })
        log.info("welcome_win", "LOGO 阶段", logo_path)
    else
        log.warn("welcome_win", "logo 资源缺失，LOGO 阶段仅显示黑底")
    end

    -- 最短停留：展满后放行入场（若 boot_ok 已就绪）
    min_timer = sys.timerStart(function()
        min_timer = nil
        min_ok = true
        try_enter()
    end, BOOT_LOGO_MIN_MS)

    -- 兜底：初始化卡死也强制入场，防止永久停在 logo
    logo_wait_timer = sys.timerStart(function()
        logo_wait_timer = nil
        log.warn("welcome_win", "初始化未在", BOOT_LOGO_MAX_WAIT_MS, "ms 内完成，兜底入场")
        boot_ok = true
        try_enter()
    end, BOOT_LOGO_MAX_WAIT_MS)

    -- 粘性标记补查：BOOT_INIT_DONE 可能早于窗口创建（事件丢不了，见 on_boot_init_done 注释）
    if _G.__boot_init_done then
        boot_ok = true
    end
    try_enter()
end

local function on_destroy()
    -- 先落闸，避免 close 之后残留的定时器再触发一次收尾
    finished = true
    if min_timer then
        sys.timerStop(min_timer)
        min_timer = nil
    end
    if logo_wait_timer then
        sys.timerStop(logo_wait_timer)
        logo_wait_timer = nil
    end
    if logo_img then
        pcall(logo_img.destroy, logo_img)
        logo_img = nil
    end
    if bg_shape then
        bg_shape:destroy()
        bg_shape = nil
    end
    window_id = nil
end

local function on_get_focus() end
local function on_lose_focus() end

local function open_handler()
    window_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_get_focus = on_get_focus,
        on_lose_focus = on_lose_focus,
    })
end

sys.subscribe("OPEN_WELCOME_WIN", open_handler)
sys.subscribe("BOOT_INIT_DONE", on_boot_init_done)
