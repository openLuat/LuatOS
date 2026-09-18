--[[
@module  reset_win
@summary 恢复出厂设置确认页面
@version 1.0
@date    2026.09.04
@author  江访
@usage
显示恢复出厂设置的确认界面：
1、警告文字说明
2、确认按钮（红色）→ 发布 FACTORY_RESET_UI → 重启
3、取消按钮（返回首页）
]]

local win_id = nil
local main_container, content
local status_label

local function on_back_click()
    if not exwin.is_active(win_id) then return end
    exwin.close(win_id)
end

-- ==================== 恢复出厂 ====================

local function do_factory_reset()
    if not exwin.is_active(win_id) then return end
    if status_label then
        status_label:set_text("正在恢复出厂设置...")
        status_label:set_color(T.COLOR_ORANGE)
    end
    log.info("reset_win", "factory reset requested")
    sys.publish("FACTORY_RESET_UI")
end

-- 等待恢复结果
local function on_factory_reset_result(ok, msg)
    if not exwin.is_active(win_id) then return end
    if status_label then
        if ok then
            status_label:set_text("恢复成功，即将重启...")
            status_label:set_color(T.COLOR_GREEN)
        else
            status_label:set_text("恢复失败：" .. (msg or "未知错误"))
            status_label:set_color(T.COLOR_DANGER)
        end
    end
end

-- ==================== 创建 UI ====================

local function create_ui()
    main_container = airui.container({ x = 0, y = 0, w = T.SCREEN_W, h = T.SCREEN_H, color = T.COLOR_BG, parent = airui.screen })
    T.titlebar(main_container, "恢复出厂设置", on_back_click)

    content = airui.container({ parent = main_container, x = 0, y = T.CONTENT_Y, w = T.SCREEN_W, h = T.CONTENT_H, color = T.COLOR_BG })

    -- 警告图标区域
    airui.label({ parent = content, x = T.MARGIN, y = 20, w = T.CARD_W, h = 30, text = "!", font_size = 36, color = T.COLOR_DANGER, align = airui.TEXT_ALIGN_CENTER })

    -- 警告文字
    airui.label({ parent = content, x = T.MARGIN, y = 58, w = T.CARD_W, h = 20, text = "此操作将恢复所有配置到出厂默认值", font_size = T.FONT_BODY, color = T.COLOR_TEXT, align = airui.TEXT_ALIGN_CENTER })
    airui.label({ parent = content, x = T.MARGIN, y = 82, w = T.CARD_W, h = 20, text = "MQTT、网络、串口、Modbus 等配置将被重置", font_size = T.FONT_SMALL, color = T.COLOR_TEXT_SECONDARY, align = airui.TEXT_ALIGN_CENTER })
    airui.label({ parent = content, x = T.MARGIN, y = 102, w = T.CARD_W, h = 20, text = "操作完成后设备将自动重启", font_size = T.FONT_SMALL, color = T.COLOR_TEXT_SECONDARY, align = airui.TEXT_ALIGN_CENTER })

    -- 状态标签
    status_label = airui.label({ parent = content, x = T.MARGIN, y = 130, w = T.CARD_W, h = 20, text = "", font_size = T.FONT_SMALL, color = T.COLOR_TEXT, align = airui.TEXT_ALIGN_CENTER })

    -- 确认按钮（红色）
    T.btn_danger(content, T.MARGIN + 60, 160, 140, 40, "确认恢复", do_factory_reset)

    -- 取消按钮（灰色）
    T.btn_primary(content, T.MARGIN + 260, 160, 140, 40, "取消", on_back_click)
end

-- ==================== 窗口生命周期 ====================

local function on_create()
    create_ui()
    sys.subscribe("FACTORY_RESET_RESULT", on_factory_reset_result)
end

local function on_destroy()
    sys.unsubscribe("FACTORY_RESET_RESULT", on_factory_reset_result)
    if main_container then main_container:destroy(); main_container = nil end
    content = nil
    status_label = nil
    win_id = nil
end

local function open_handler()
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
    })
end

sys.subscribe("OPEN_RESET_WIN", open_handler)
