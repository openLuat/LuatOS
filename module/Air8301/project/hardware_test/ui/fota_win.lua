--[[
@module  fota_win
@summary FOTA远程升级页面
@version 1.0
@date    2026.09.04
@author  江访
@usage
显示固件版本信息、IoT配置、升级状态和历史记录。
]]

local win_id = nil
local main_container, content
local core_ver_label, script_ver_label, status_label, history_label

local function on_back_click()
    if not exwin.is_active(win_id) then return end
    exwin.close(win_id)
end

local function on_check_click()
    if not exwin.is_active(win_id) then return end
    status_label:set_text("正在检测...")
    status_label:set_color(T.COLOR_TEXT)
    sys.publish("fota_cmd_check")
end

local function create_ui()
    main_container = airui.container({ x = 0, y = 0, w = T.SCREEN_W, h = T.SCREEN_H, color = T.COLOR_BG, parent = airui.screen })

    T.titlebar(main_container, "远程升级", on_back_click)

    content = airui.container({ parent = main_container, x = 0, y = T.CONTENT_Y, w = T.SCREEN_W, h = T.CONTENT_H, color = T.COLOR_BG })

    -- 固件版本
    local c1 = airui.container({ parent = content, x = T.MARGIN, y = 10, w = T.CARD_W, h = 48, color = T.COLOR_CARD, radius = T.CARD_RADIUS })
    airui.label({ parent = c1, x = 15, y = 6, w = 100, h = 18, text = "内核版本", font_size = T.FONT_SMALL, color = T.COLOR_TEXT_SECONDARY, align = airui.TEXT_ALIGN_LEFT })
    core_ver_label = airui.label({ parent = c1, x = 15, y = 26, w = 400, h = 18, text = "--", font_size = T.FONT_BODY, color = T.COLOR_TEXT, align = airui.TEXT_ALIGN_LEFT })

    local c2 = airui.container({ parent = content, x = T.MARGIN, y = 66, w = T.CARD_W, h = 48, color = T.COLOR_CARD, radius = T.CARD_RADIUS })
    airui.label({ parent = c2, x = 15, y = 6, w = 100, h = 18, text = "脚本版本", font_size = T.FONT_SMALL, color = T.COLOR_TEXT_SECONDARY, align = airui.TEXT_ALIGN_LEFT })
    script_ver_label = airui.label({ parent = c2, x = 15, y = 26, w = 400, h = 18, text = "--", font_size = T.FONT_BODY, color = T.COLOR_TEXT, align = airui.TEXT_ALIGN_LEFT })

    -- 升级状态
    local c3 = airui.container({ parent = content, x = T.MARGIN, y = 122, w = T.CARD_W, h = 48, color = T.COLOR_CARD, radius = T.CARD_RADIUS })
    airui.label({ parent = c3, x = 15, y = 6, w = 100, h = 18, text = "升级状态", font_size = T.FONT_SMALL, color = T.COLOR_TEXT_SECONDARY, align = airui.TEXT_ALIGN_LEFT })
    status_label = airui.label({ parent = c3, x = 15, y = 26, w = 400, h = 18, text = "就绪", font_size = T.FONT_BODY, color = T.COLOR_TEXT, align = airui.TEXT_ALIGN_LEFT })

    -- 检测按钮
    local btn = T.btn_primary(content, "立即检测", T.MARGIN, 178, T.CARD_W, 38, on_check_click)
end

local function on_create()
    create_ui()
    sys.publish("fota_cmd_get_version")
    sys.publish("fota_cmd_get_history")
end

local function on_destroy()
    if main_container then main_container:destroy(); main_container = nil end
    core_ver_label = nil; script_ver_label = nil; status_label = nil; history_label = nil; win_id = nil
end

local function on_get_focus()
    sys.publish("fota_cmd_get_version")
end
local function on_lose_focus() end

-- 版本信息更新
sys.subscribe("fota_version_rsp", function(data)
    if not core_ver_label then return end
    core_ver_label:set_text(data.core_version or "--")
    script_ver_label:set_text(data.script_version or "--")
end)

-- FOTA状态更新
sys.subscribe("fota_status_checking", function(msg)
    if not status_label then return end
    status_label:set_text(msg or "正在检测...")
    status_label:set_color(T.COLOR_PRIMARY)
end)

sys.subscribe("fota_status_downloading", function(msg)
    if not status_label then return end
    status_label:set_text(msg or "下载中...")
    status_label:set_color(T.COLOR_PRIMARY)
end)

sys.subscribe("fota_status_success", function(msg)
    if not status_label then return end
    status_label:set_text(msg or "升级成功")
    status_label:set_color(T.COLOR_GREEN)
end)

sys.subscribe("fota_status_no_new_version", function(msg)
    if not status_label then return end
    status_label:set_text(msg or "已是最新版本")
    status_label:set_color(T.COLOR_GREEN)
end)

sys.subscribe("fota_status_fail", function(msg)
    if not status_label then return end
    status_label:set_text(msg or "升级失败")
    status_label:set_color(T.COLOR_DANGER)
end)

local function open_handler()
    win_id = exwin.open({ on_create = on_create, on_destroy = on_destroy, on_lose_focus = on_lose_focus, on_get_focus = on_get_focus })
end

sys.subscribe("OPEN_FOTA_WIN", open_handler)
