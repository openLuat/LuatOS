--[[
@module  backup_win
@summary 备份管理页面
@version 1.0
@date    2026.09.04
@author  江访
@usage
显示备份文件列表，支持手动备份、恢复、删除操作。
]]

local win_id = nil
local main_container, content
local list_container, files_label, storage_label
local backup_files = {}

local function on_back_click()
    if not exwin.is_active(win_id) then return end
    exwin.close(win_id)
end

local function on_backup_click()
    if not exwin.is_active(win_id) then return end
    sys.publish("BACKUP_CREATE_NOW")
end

local function on_restore_click()
    if not exwin.is_active(win_id) then return end
    -- 恢复最新的备份
    if #backup_files > 0 then
        local latest = backup_files[#backup_files]
        sys.publish("BACKUP_RESTORE_NOW", latest.name)
    end
end

local function refresh_list()
    sys.publish("BACKUP_LIST_QUERY")
    sys.publish("BACKUP_STORAGE_QUERY")
end

local function create_ui()
    main_container = airui.container({ x = 0, y = 0, w = T.SCREEN_W, h = T.SCREEN_H, color = T.COLOR_BG, parent = airui.screen })

    T.titlebar(main_container, "备份管理", on_back_click)

    content = airui.container({ parent = main_container, x = 0, y = T.CONTENT_Y, w = T.SCREEN_W, h = T.CONTENT_H, color = T.COLOR_BG })

    -- 存储信息
    local c1 = airui.container({ parent = content, x = T.MARGIN, y = 8, w = T.CARD_W, h = 36, color = T.COLOR_CARD, radius = T.CARD_RADIUS })
    airui.label({ parent = c1, x = 15, y = 8, w = 80, h = 20, text = "备份目录", font_size = T.FONT_SMALL, color = T.COLOR_TEXT_SECONDARY, align = airui.TEXT_ALIGN_LEFT })
    storage_label = airui.label({ parent = c1, x = 100, y = 8, w = 340, h = 20, text = "查询中...", font_size = T.FONT_SMALL, color = T.COLOR_TEXT, align = airui.TEXT_ALIGN_LEFT })

    -- 备份文件列表区域
    files_label = airui.label({ parent = content, x = T.MARGIN, y = 50, w = T.CARD_W, h = 120, text = "暂无备份文件", font_size = T.FONT_SMALL, color = T.COLOR_TEXT_SECONDARY, align = airui.TEXT_ALIGN_CENTER })

    -- 操作按钮行
    local btn_y = 180
    local btn_w = 140
    local btn_gap = 20
    local btn_x = T.MARGIN

    T.btn_primary(content, "立即备份", btn_x, btn_y, btn_w, 36, on_backup_click)
    T.btn_success(content, "恢复最新", btn_x + btn_w + btn_gap, btn_y, btn_w, 36, on_restore_click)
end

local function on_create()
    create_ui()
    refresh_list()
end

local function on_destroy()
    if main_container then main_container:destroy(); main_container = nil end
    list_container = nil; files_label = nil; storage_label = nil; win_id = nil
    backup_files = {}
end

local function on_get_focus()
    refresh_list()
end
local function on_lose_focus() end

-- 备份列表更新
sys.subscribe("BACKUP_LIST_UPDATE", function(files)
    backup_files = files or {}
    if not files_label then return end
    if #backup_files == 0 then
        files_label:set_text("暂无备份文件")
    else
        local text = ""
        for i = 1, math.min(#backup_files, 5) do
            local f = backup_files[i]
            text = text .. f.time .. "  " .. (f.size and math.floor(f.size / 1024) .. "KB" or "")
            if i < math.min(#backup_files, 5) then text = text .. "\n" end
        end
        if #backup_files > 5 then
            text = text .. "\n...共" .. #backup_files .. "个备份"
        end
        files_label:set_text(text)
    end
end)

-- 存储空间更新
sys.subscribe("BACKUP_STORAGE_UPDATE", function(used, total)
    if not storage_label then return end
    storage_label:set_text(string.format("%.1fKB / %.1fKB", used / 1024, total / 1024))
end)

-- 恢复结果
sys.subscribe("BACKUP_RESTORE_RESULT", function(ok, err)
    if ok then
        sys.publish("BUZZER_BEEP_REQUEST")
    end
end)

local function open_handler()
    win_id = exwin.open({ on_create = on_create, on_destroy = on_destroy, on_lose_focus = on_lose_focus, on_get_focus = on_get_focus })
end

sys.subscribe("OPEN_BACKUP_WIN", open_handler)
