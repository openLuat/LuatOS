--[[
@module  buzzer_win
@summary 蜂鸣器测试页，点击就响0.5秒（8301出厂固件）
@version 1.0
@date    2026.10.08
@author  江访

@usage
点击测试按钮蜂鸣器响0.5秒，固定2700Hz；点击"播放歌曲"按钮演奏开机曲目（约18秒）。

视觉：ui_theme 深色玻璃态（说明面板 + 两枚通栏按钮）。
]]

local theme = require "ui_theme"

local win_id = nil
local main_container, content

-- 面板几何（内容区 464×210）
local INFO_H = 64
local BTN_H  = 34

--[[
导航栏返回按钮点击

@local
@function on_back_click
]]
local function on_back_click()
    if not exwin.is_active(win_id) then return end
    exwin.close(win_id)
end

--[[
测试按钮点击：响 0.5 秒

@local
@function on_test_click
]]
local function on_test_click()
    if not exwin.is_active(win_id) then return end
    sys.publish("BUZZER_BEEP_REQUEST")
end

--[[
播放歌曲按钮点击回调：请求演奏曲目（有源蜂鸣器节奏版，约18秒）

@local
@function on_music_click
]]
local function on_music_click()
    if not exwin.is_active(win_id) then return end
    sys.publish("BUZZER_MUSIC_REQUEST")
end

--[[
创建UI界面

@local
@function create_ui
]]
local function create_ui()
    local ctx = theme.page({ title = "蜂鸣器", on_back = on_back_click })
    main_container = ctx.base
    content = ctx.base

    -- 说明面板
    local info = theme.card(ctx.base, {
        x = ctx.x, y = ctx.y, w = ctx.w, h = INFO_H,
        color = theme.C.panel, radius = theme.R.lg, border = theme.C.stroke_soft,
    })
    theme.label(info, {
        x = 12, y = 8, w = ctx.w - 24, h = 19,
        text = "蜂鸣器测试", px_size = 16, color = theme.C.t3,
    })
    theme.label(info, {
        x = 12, y = 32, w = ctx.w - 24, h = 19,
        text = "有源蜂鸣器 | PWM2 | 2700Hz | 占空比50%",
        px_size = 16, color = theme.C.t1,
    })

    -- 测试按钮（危险色）
    local by = ctx.y + INFO_H + 10
    theme.btn(ctx.base, {
        x = ctx.x, y = by, w = ctx.w, h = BTN_H,
        text = "点击测试蜂鸣器（0.5秒）",
        bg = theme.SEM.danger, fg = theme.C.on_amber,
        on_click = on_test_click,
    })

    -- 播放歌曲按钮（主色）
    theme.btn(ctx.base, {
        x = ctx.x, y = by + BTN_H + 10, w = ctx.w, h = BTN_H,
        text = "播放歌曲（约18秒）",
        on_click = on_music_click,
    })
end

--[[
窗口创建回调

@local
@function on_create
]]
local function on_create()
    create_ui()
end

--[[
窗口销毁回调

@local
@function on_destroy
]]
local function on_destroy()
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    content = nil
    win_id = nil
end

--[[
窗口获得焦点回调

@local
@function on_get_focus
]]
local function on_get_focus() end

--[[
窗口失去焦点回调

@local
@function on_lose_focus
]]
local function on_lose_focus() end

--[[
OPEN_BUZZER_WIN 消息处理器

@local
@function open_handler
]]
local function open_handler()
    -- 单实例保护：避免同页多实例并存时互相覆盖 win_id（会使点击准入判定失效）
    if win_id and exwin.is_active(win_id) then return end
    if win_id then
        exwin.close(win_id)
        win_id = nil
    end
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_lose_focus = on_lose_focus,
        on_get_focus = on_get_focus,
    })
end

sys.subscribe("OPEN_BUZZER_WIN", open_handler)
