--[[
@module  welcome_win
@summary 开机欢迎页 —— 黑底 + logo，初始化完成后进入桌面
@version 5.0
@date    2026.10.05
@author  江访
@usage
订阅: OPEN_WELCOME_WIN  → 创建欢迎页（黑底 + logo 图）
订阅: BOOT_INIT_DONE    → 初始化完成
发布: OPEN_IDLE_WIN     → 收尾后发布，触发桌面窗口
]]

local LOGO_SIZE = 128
-- logo 最短停留
local BOOT_LOGO_MIN_MS = 500
-- 初始化兜底超时（含初始化卡死）
local BOOT_LOGO_MAX_WAIT_MS = 3000

local window_id = nil
local bg_shape
local logo_img

-- 只收尾一次的闸门
local finished = false

-- 入场条件：最短停留展满(min_ok) 且 初始化完成(boot_ok)
local min_ok = false
local boot_ok = false
local min_timer = nil
local logo_wait_timer = nil

-- 收尾进入桌面（只生效一次）
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

-- 入场闸门：min_ok 与 boot_ok 同时满足才收尾
local function try_enter()
    if not (min_ok and boot_ok) then return end
    if finished or not window_id then return end
    finish("就绪")
end

-- 初始化完成（boot_ui 发布；窗口未建时由 on_create 查粘性标记补上）
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

    -- 黑色全屏背景
    bg_shape = airui.shape({
        x = 0, y = 0, w = screen_w, h = screen_h,
        items = {
            { type = "rect", x = 0, y = 0, w = screen_w, h = screen_h,
              fill = true, fill_color = 0x000000, color = 0x000000 },
        },
    })

    -- logo 居中 1:1 显示；资源缺失只显示黑底
    local logo_path = nil
    for _, p in ipairs({ "/luadb/logo.png", "/logo.png" }) do
        if io.exists(p) then
            logo_path = p
            break
        end
    end
    if logo_path then
        logo_img = airui.image({
            x = math.floor((screen_w - LOGO_SIZE) / 2),
            y = math.floor((screen_h - LOGO_SIZE) / 2),
            w = LOGO_SIZE, h = LOGO_SIZE,
            src = logo_path,
        })
        log.info("welcome_win", "LOGO 阶段", logo_path)
    else
        log.warn("welcome_win", "logo 资源缺失，仅显示黑底")
    end

    -- 最短停留计时
    min_timer = sys.timerStart(function()
        min_timer = nil
        min_ok = true
        try_enter()
    end, BOOT_LOGO_MIN_MS)

    -- 兜底超时强制入场
    logo_wait_timer = sys.timerStart(function()
        logo_wait_timer = nil
        log.warn("welcome_win", "初始化未在", BOOT_LOGO_MAX_WAIT_MS, "ms 内完成，兜底入场")
        boot_ok = true
        try_enter()
    end, BOOT_LOGO_MAX_WAIT_MS)

    -- 粘性标记补查
    if _G.__boot_init_done then
        boot_ok = true
    end
    try_enter()
end

local function on_destroy()
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
