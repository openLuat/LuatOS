--[[
@module  fota_win
@summary FOTA 远程升级页面（8301出厂固件）
@version 1.0
@date    2026.09.22
@author  江访
@usage
显示脚本版本、升级状态与进度，提供"检测更新"按钮。
- 每 2 秒轮询 fota_app.get_status() 刷新显示
]]

local win_id = nil
local main_container, content
local ver_label, status_label, progress_bar, history_label

local fota_app = require "fota_app"

-- 刷新定时器
local refresh_timer = nil

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
检测更新按钮点击

@local
@function on_check_click
]]
local function on_check_click()
    if not exwin.is_active(win_id) then return end
    if status_label then
        status_label:set_text("正在检测...")
        status_label:set_color(T.COLOR_PRIMARY)
    end
    fota_app.check()
end

--[[
刷新 FOTA 状态显示

@local
@function refresh_status
]]
local function refresh_status()
    if not exwin.is_active(win_id) then return end
    local st = fota_app.get_status() or {}

    if ver_label then
        ver_label:set_text(tostring(VERSION or "--"))
    end

    if status_label then
        local msg = st.msg or st.stage or "--"
        status_label:set_text(msg)
        if st.stage == "error" then
            status_label:set_color(T.COLOR_DANGER)
        elseif st.stage == "download_done" then
            status_label:set_color(T.COLOR_GREEN)
        else
            status_label:set_color(T.COLOR_TEXT)
        end
    end

    if progress_bar then
        progress_bar:set_value(st.progress or 0)
    end

    if history_label and st.history and #st.history > 0 then
        local lines = {}
        for i, item in ipairs(st.history) do
            if i > 4 then break end
            lines[#lines + 1] = tostring(item.time or "--") .. "  " .. tostring(item.ver or "--") .. "  " .. tostring(item.status or "")
        end
        history_label:set_text(table.concat(lines, "\n"))
    end
end

-- 定时刷新回调
local function refresh_timer_cb()
    refresh_status()
end

--[[
创建 FOTA 页面 UI

@local
@function create_ui
]]
local function create_ui()
    main_container = airui.container({ x = 0, y = 0, w = T.SCREEN_W, h = T.SCREEN_H, color = T.COLOR_BG, parent = airui.screen })

    T.titlebar(main_container, "远程升级", on_back_click)

    content = airui.container({ parent = main_container, x = 0, y = T.CONTENT_Y, w = T.SCREEN_W, h = T.CONTENT_H, color = T.COLOR_BG })

    local _, _, ver_content = T.info_card(content, 6, 46, "当前脚本版本", "--")
    ver_label = ver_content

    local _, _, status_content = T.info_card(content, 58, 46, "升级状态", "就绪")
    status_label = status_content

    progress_bar = airui.bar({
        parent = content,
        x = T.MARGIN, y = 112, w = T.CARD_W, h = 20,
        min = 0, max = 100, value = 0,
        indicator_color = T.COLOR_PRIMARY,
    })

    T.btn_primary(content, T.MARGIN, 140, T.CARD_W, 34, "立即检测更新", on_check_click)

    local _, _, history_content = T.info_card(content, 180, 40, "升级历史", "暂无记录")
    history_label = history_content

    refresh_status()
end

--[[
窗口创建回调

@local
@function on_create
]]
local function on_create()
    create_ui()
    if not refresh_timer then
        refresh_timer = sys.timerLoopStart(refresh_timer_cb, 2000)
    end
end

--[[
窗口销毁回调

@local
@function on_destroy
]]
local function on_destroy()
    if refresh_timer then
        sys.timerStop(refresh_timer)
        refresh_timer = nil
    end
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    content = nil
    ver_label = nil
    status_label = nil
    progress_bar = nil
    history_label = nil
    win_id = nil
end

--[[
窗口获得焦点回调

@local
@function on_get_focus
]]
local function on_get_focus()
    refresh_status()
end

--[[
窗口失去焦点回调

@local
@function on_lose_focus
]]
local function on_lose_focus() end

--[[
OPEN_FOTA_WIN 消息处理器

@local
@function open_handler
]]
local function open_handler()
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_lose_focus = on_lose_focus,
        on_get_focus = on_get_focus,
    })
end

sys.subscribe("OPEN_FOTA_WIN", open_handler)
