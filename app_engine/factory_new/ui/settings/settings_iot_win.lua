--[[
@module  settings_iot_win
@summary IOT 账号设置页面
@version 1.4
@date    2026.05.09
@author  江访
]]

local window_id = nil
local main_container
local soft_keyboard
local content_area
local first_open = true

local screen_w, screen_h = 480, 800
local margin, card_w, padding, row_gap, label_w, input_w, input_h, row_h, btn_w, btn_h, font_size, font_size2

local titlebar = require "settings_titlebar"

-- TabOS 深色玻璃态调色板（原浅色常量 → 主题令牌）
local theme = require "ui_theme"

-- 主题令牌动态代理：换主题后自动取到新色值
-- （写成 local X = theme.C.y 会在 require 时固化，换肤不生效）
local CLR = theme.live()

local function update_screen_size()
    local rot = airui.get_rotation()
    local pw, ph = lcd.getSize()
    if rot == 0 or rot == 180 then
        screen_w, screen_h = pw, ph
    else
        screen_w, screen_h = ph, pw
    end
    -- 宽屏有左栏时收窄到右侧内容区（窄屏原样返回），下方全部比例式几何随之自适应
    screen_w, screen_h = theme.content_fit(screen_w, screen_h)
    local d = math.min(screen_w, screen_h)
    margin = theme.page_margin()
    card_w   = screen_w - 2 * margin
    padding  = math.floor(d * 0.015)
    row_gap  = math.floor(d * 0.015)
    label_w   = math.floor(card_w * 0.28)
    input_w   = card_w - label_w - math.floor(screen_w * 0.08)
    input_h   = math.max(math.floor(d * 0.06), 30)
    row_h   = input_h + 2 * padding
    btn_w   = math.floor(card_w * 0.7)
    btn_h   = math.max(math.floor(d * 0.06), 30)
    -- 原按屏幕短边比例取字号（d*0.036 / d*0.030），与全局密度体系是两套缩放逻辑，
    -- 统一改用语义档位（与 settings_fota_win 保持一致）
    font_size   = theme.fs("h3")        -- 输入控件文字
    font_size2  = theme.fs("caption")   -- 标签 / 说明文字
end

local function rebuild_content(info)
    if not main_container then return end
    if content_area then
        content_area:destroy()
        content_area = nil
    end
    soft_keyboard = nil
    content_area = airui.container({
        parent = main_container,
        x = 0, y = math.floor(60 * _G.density_scale),
        w = screen_w, h = screen_h - math.floor(60 * _G.density_scale),
        color = CLR.surface, color_opacity = 0,
        scrollable = true
    })

    if info and not info.is_guest then
        local info_card = airui.container({
            parent = content_area,
            x = margin, y = math.floor(screen_h * 0.06),
            w = card_w, h = math.floor(screen_h * 0.35),
            color = CLR.surface, color_opacity = theme.OPA.glass, border_color = CLR.stroke, border_width = 1,
            radius = math.floor(row_h * 0.15)
        })
        local inner_pad = math.floor(card_w * 0.08)
        local info_label_h = math.floor(screen_h * 0.045)
        local info_y = math.floor(screen_h * 0.04)

        airui.label({
            parent = info_card,
            x = inner_pad, y = info_y,
            w = card_w - 2 * inner_pad, h = info_label_h,
            text = "已登录",
            font_size = font_size,
            color = CLR.primary,
            align = airui.TEXT_ALIGN_CENTER
        })

        info_y = info_y + info_label_h + math.floor(screen_h * 0.03)
        airui.label({
            parent = info_card,
            x = inner_pad, y = info_y,
            w = math.floor(card_w * 0.25), h = info_label_h,
            text = "账号",
            font_size = font_size2,
            color = CLR.t2,
            align = airui.TEXT_ALIGN_LEFT
        })
        local account_text = info.account or ""
        if #account_text > 7 then
            account_text = account_text:sub(1, 3) .. string.rep("*", #account_text - 7) .. account_text:sub(-4)
        end
        airui.label({
            parent = info_card,
            x = inner_pad + math.floor(card_w * 0.25), y = info_y,
            w = card_w - 2 * inner_pad - math.floor(card_w * 0.25), h = info_label_h,
            text = account_text,
            font_size = font_size2,
            color = CLR.t1,
            align = airui.TEXT_ALIGN_LEFT
        })

        info_y = info_y + info_label_h + math.floor(screen_h * 0.02)
        airui.label({
            parent = info_card,
            x = inner_pad, y = info_y,
            w = math.floor(card_w * 0.25), h = info_label_h,
            text = "昵称",
            font_size = font_size2,
            color = CLR.t2,
            align = airui.TEXT_ALIGN_LEFT
        })
        airui.label({
            parent = info_card,
            x = inner_pad + math.floor(card_w * 0.25), y = info_y,
            w = card_w - 2 * inner_pad - math.floor(card_w * 0.25), h = info_label_h,
            text = info.nickname or "",
            font_size = font_size2,
            color = CLR.t1,
            align = airui.TEXT_ALIGN_LEFT
        })

        local iby = info_y + info_label_h + math.floor(screen_h * 0.06)
        local ibx = math.floor((card_w - btn_w) / 2)
        airui.button({
            parent = info_card,
            x = ibx, y = iby,
            w = btn_w, h = btn_h,
            text = "登出",
            font_size = font_size2,
            style = {
                bg_color = CLR.rose,
                pressed_bg_color = theme.C.rose_deep,
                text_color = CLR.white,
                radius = math.floor(btn_h * 0.2),
                border_width = 0
            },
            on_click = function()
                sys.publish("IOT_LOGOUT_REQUEST")
            end
        })
    else
        soft_keyboard = theme.keyboard({
            x = 0, y = -math.floor(screen_h * 0.03),
            w = screen_w, h = math.floor(screen_h * 0.32),
            mode = "text",
            auto_hide = true,
            on_commit = function(self) self:hide() end
        })
        local y = math.floor(screen_h * 0.03)
        local row1 = airui.container({
            parent = content_area,
            x = margin, y = y,
            w = card_w, h = row_h,
            color = CLR.surface, color_opacity = theme.OPA.glass, border_color = CLR.stroke, border_width = 1,
            radius = math.floor(row_h * 0.15)
        })
        airui.label({
            parent = row1,
            x = math.floor(card_w * 0.05), y = padding,
            w = label_w, h = input_h,
            text = "账号",
            font_size = font_size2,
            color = CLR.t1,
            align = airui.TEXT_ALIGN_LEFT
        })
        local name_input = theme.input({
            parent = row1,
            x = label_w + math.floor(card_w * 0.05), y = padding,
            w = input_w, h = input_h,
            text = "",
            font_size = font_size2,
            keyboard = soft_keyboard
        })

        y = y + row_h + row_gap
        local row2 = airui.container({
            parent = content_area,
            x = margin, y = y,
            w = card_w, h = row_h,
            color = CLR.surface, color_opacity = theme.OPA.glass, border_color = CLR.stroke, border_width = 1,
            radius = math.floor(row_h * 0.15)
        })
        airui.label({
            parent = row2,
            x = math.floor(card_w * 0.05), y = padding,
            w = label_w, h = input_h,
            text = "密码",
            font_size = font_size2,
            color = CLR.t1,
            align = airui.TEXT_ALIGN_LEFT
        })
        local pwd_input = theme.input({
            parent = row2,
            x = label_w + math.floor(card_w * 0.05), y = padding,
            w = input_w, h = input_h,
            text = "",
            font_size = font_size2,
            password_mode = true,
            keyboard = soft_keyboard
        })

        y = y + row_h + math.floor(screen_h * 0.08)
        local bx = math.floor((card_w - btn_w) / 2)
        airui.button({
            parent = content_area,
            x = bx, y = y,
            w = btn_w, h = btn_h,
            text = "登录",
            font_size = font_size2,
            style = {
                bg_color = CLR.primary,
                pressed_bg_color = theme.C.amber_deep,
                text_color = CLR.white,
                radius = math.floor(btn_h * 0.2),
                border_width = 0
            },
            on_click = function()
                local account = name_input:get_text() or ""
                local password = pwd_input:get_text() or ""
                if #account == 0 or #password == 0 then
                    airui.msgbox({
                        parent = main_container,
                        title = "提示",
                        text = "账号和密码不能为空",
                        buttons = {"确定"},
                        on_action = function(self) self:destroy() end
                    })
                    return
                end
                sys.publish("IOT_LOGIN_REQUEST", account, password)
            end
        })
    end
end

local function update_account_info(info)
    if not info then return end
    rebuild_content(info)
end

local function on_login_resp(response)
    if not response then return end
    if response.success then
        update_account_info({account = response.account, nickname = response.nickname, is_guest = false})
    else
        airui.msgbox({
            parent = main_container,
            title = "登录失败",
            text = response.error or "未知错误",
            buttons = {"确定"},
            on_action = function(self) self:destroy() end
        })
    end
end

local function on_logout_resp(response)
    update_account_info({account = "", nickname = "", is_guest = true})
end

local function build_ui()
    update_screen_size()

main_container = theme.page_bg(airui.screen, screen_w, screen_h)

    local _, th = titlebar.create(main_container, "IOT账号", screen_w, function() exwin.close(window_id) end)

    if soft_keyboard then soft_keyboard = nil end

    sys.publish("IOT_GET_ACCOUNT_INFO")
end

local function on_create()
    sys.subscribe("IOT_LOGIN_RESULT", on_login_resp)
    sys.subscribe("IOT_LOGOUT_RESULT", on_logout_resp)
    sys.subscribe("IOT_ACCOUNT_INFO", update_account_info)
    build_ui()
end

local function on_destroy()
    sys.unsubscribe("IOT_LOGIN_RESULT", on_login_resp)
    sys.unsubscribe("IOT_LOGOUT_RESULT", on_logout_resp)
    sys.unsubscribe("IOT_ACCOUNT_INFO", update_account_info)
    if content_area then content_area:destroy(); content_area = nil end
    if main_container then main_container:destroy(); main_container = nil end
    soft_keyboard = nil
end

local function on_get_focus() end
local function on_lose_focus() end

local function open_handler()
    window_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_lose_focus = on_lose_focus,
        on_get_focus = on_get_focus,
    })
end

sys.subscribe("OPEN_IOT_WIN", open_handler)
