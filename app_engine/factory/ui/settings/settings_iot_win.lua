--[[
@module  settings_iot_win
@summary IOT 账号设置页面  
@version 1.3
@date    2026.05.09
@author  江访
]]
-- naming: fn(2-5char), var(2-4char)

local wid = nil
local mc
local kv
local ct

local sw, sh = 480, 800
local mg, cw, pad, gap, lw, iw, ih, rh, bw, bh, fs, fs2

local COLOR_PRIMARY        = 0x007AFF
local COLOR_BG             = 0xF5F5F5
local COLOR_CARD           = 0xFFFFFF
local COLOR_TEXT           = 0x333333
local COLOR_TEXT_SECONDARY = 0x757575
local COLOR_WHITE          = 0xFFFFFF
local COLOR_DANGER         = 0xE63946

local function up_sz()
    local rot = airui.get_rotation()
    local pw, ph = lcd.getSize()
    if rot == 0 or rot == 180 then
        sw, sh = pw, ph
    else
        sw, sh = ph, pw
    end
    local d = math.min(sw, sh)
    mg   = math.floor(sw * 0.03)
    cw   = sw - 2 * mg
    pad  = math.floor(d * 0.015)
    gap  = math.floor(d * 0.015)
    lw   = math.floor(cw * 0.28)
    iw   = cw - lw - math.floor(sw * 0.08)
    ih   = math.max(math.floor(d * 0.06), 30)
    rh   = ih + 2 * pad
    bw   = math.floor(cw * 0.7)
    bh   = math.max(math.floor(d * 0.06), 30)
    fs   = math.max(math.floor(d * 0.036), 14)
    fs2  = math.max(math.floor(d * 0.030), 12)
end

local function rbct(info)
    if ct then ct:destroy() end
    ct = airui.container({
        parent = mc,
        x = 0, y = math.floor(60 * _G.density_scale),
        w = sw, h = sh - math.floor(60 * _G.density_scale),
        color = COLOR_BG,
        scrollable = true
    })

    if info and not info.is_guest then
        local ic = airui.container({
            parent = ct,
            x = mg, y = math.floor(sh * 0.06),
            w = cw, h = math.floor(sh * 0.35),
            color = COLOR_CARD,
            radius = math.floor(rh * 0.15)
        })
        local ipd = math.floor(cw * 0.08)
        local ilh = math.floor(sh * 0.045)
        local iy = math.floor(sh * 0.04)

        airui.label({
            parent = ic,
            x = ipd, y = iy,
            w = cw - 2 * ipd, h = ilh,
            text = "已登录",
            font_size = fs,
            color = COLOR_PRIMARY,
            align = airui.TEXT_ALIGN_CENTER
        })

        iy = iy + ilh + math.floor(sh * 0.03)
        airui.label({
            parent = ic,
            x = ipd, y = iy,
            w = math.floor(cw * 0.25), h = ilh,
            text = "账号",
            font_size = fs2,
            color = COLOR_TEXT_SECONDARY,
            align = airui.TEXT_ALIGN_LEFT
        })
        local ac = info.account or ""
        if #ac > 7 then
            ac = ac:sub(1, 3) .. string.rep("*", #ac - 7) .. ac:sub(-4)
        end
        airui.label({
            parent = ic,
            x = ipd + math.floor(cw * 0.25), y = iy,
            w = cw - 2 * ipd - math.floor(cw * 0.25), h = ilh,
            text = ac,
            font_size = fs2,
            color = COLOR_TEXT,
            align = airui.TEXT_ALIGN_LEFT
        })

        iy = iy + ilh + math.floor(sh * 0.02)
        airui.label({
            parent = ic,
            x = ipd, y = iy,
            w = math.floor(cw * 0.25), h = ilh,
            text = "昵称",
            font_size = fs2,
            color = COLOR_TEXT_SECONDARY,
            align = airui.TEXT_ALIGN_LEFT
        })
        airui.label({
            parent = ic,
            x = ipd + math.floor(cw * 0.25), y = iy,
            w = cw - 2 * ipd - math.floor(cw * 0.25), h = ilh,
            text = info.nickname or "",
            font_size = fs2,
            color = COLOR_TEXT,
            align = airui.TEXT_ALIGN_LEFT
        })

        local iby = iy + ilh + math.floor(sh * 0.06)
        local ibx = math.floor((cw - bw) / 2)
        airui.button({
            parent = ic,
            x = ibx, y = iby,
            w = bw, h = bh,
            text = "登出",
            font_size = fs2,
            style = {
                bg_color = COLOR_DANGER,
                pressed_bg_color = 0xC62828,
                text_color = COLOR_WHITE,
                radius = math.floor(bh * 0.2),
                border_width = 0
            },
            on_click = function()
                sys.publish("IOT_LOGOUT_REQUEST")
            end
        })
    else
        local y = math.floor(sh * 0.03)
        local r1 = airui.container({
            parent = ct,
            x = mg, y = y,
            w = cw, h = rh,
            color = COLOR_CARD,
            radius = math.floor(rh * 0.15)
        })
        airui.label({
            parent = r1,
            x = math.floor(cw * 0.05), y = pad,
            w = lw, h = ih,
            text = "账号",
            font_size = fs2,
            color = COLOR_TEXT,
            align = airui.TEXT_ALIGN_LEFT
        })
        local inp1 = airui.textarea({
            parent = r1,
            x = lw + math.floor(cw * 0.05), y = pad,
            w = iw, h = ih,
            text = "",
            font_size = fs2,
            keyboard = kv
        })

        y = y + rh + gap
        local r2 = airui.container({
            parent = ct,
            x = mg, y = y,
            w = cw, h = rh,
            color = COLOR_CARD,
            radius = math.floor(rh * 0.15)
        })
        airui.label({
            parent = r2,
            x = math.floor(cw * 0.05), y = pad,
            w = lw, h = ih,
            text = "密码",
            font_size = fs2,
            color = COLOR_TEXT,
            align = airui.TEXT_ALIGN_LEFT
        })
        local inp2 = airui.textarea({
            parent = r2,
            x = lw + math.floor(cw * 0.05), y = pad,
            w = iw, h = ih,
            text = "",
            font_size = fs2,
            password_mode = true,
            keyboard = kv
        })

        y = y + rh + math.floor(sh * 0.08)
        local bx = math.floor((cw - bw) / 2)
        airui.button({
            parent = ct,
            x = bx, y = y,
            w = bw, h = bh,
            text = "登录",
            font_size = fs2,
            style = {
                bg_color = COLOR_PRIMARY,
                pressed_bg_color = 0x0056B3,
                text_color = COLOR_WHITE,
                radius = math.floor(bh * 0.2),
                border_width = 0
            },
            on_click = function()
                local acc = inp1:get_text() or ""
                local pwd = inp2:get_text() or ""
                if #acc == 0 or #pwd == 0 then
                    airui.msgbox({
                        parent = mc,
                        title = "提示",
                        text = "账号和密码不能为空",
                        buttons = {"确定"},
                        on_action = function(self) self:destroy() end
                    })
                    return
                end
                sys.publish("IOT_LOGIN_REQUEST", acc, pwd)
            end
        })
    end
end

local function up_info(info)
    if not info then return end
    rbct(info)
end

local function on_login_resp(resp)
    if not resp then return end
    if resp.success then
        up_info({account = resp.account, nickname = resp.nickname, is_guest = false})
    else
        airui.msgbox({
            parent = mc,
            title = "登录失败",
            text = resp.error or "未知错误",
            buttons = {"确定"},
            on_action = function(self) self:destroy() end
        })
    end
end

local function on_logout_resp(resp)
    up_info({account = "", nickname = "", is_guest = true})
end

local function cui()
    up_sz()

    mc = airui.container({
        x = 0, y = 0,
        w = sw, h = sh,
        color = COLOR_BG,
        parent = airui.screen
    })

    local th = math.floor(60 * _G.density_scale)
    local tb = airui.container({
        parent = mc,
        x = 0, y = 0,
        w = sw, h = th,
        color = COLOR_PRIMARY
    })
    local bb = airui.container({
        parent = tb,
        x = 10, y = 10,
        w = math.floor(50 * _G.density_scale), h = math.floor(40 * _G.density_scale),
        color = COLOR_PRIMARY,
        on_click = function() exwin.close(wid) end
    })
    airui.label({
        parent = bb,
        x = 0, y = math.floor(5 * _G.density_scale),
        w = math.floor(50 * _G.density_scale), h = math.floor(30 * _G.density_scale),
        text = "<",
        font_size = math.floor(28 * _G.density_scale),
        color = COLOR_WHITE,
        align = airui.TEXT_ALIGN_CENTER
    })
    airui.label({
        parent = tb,
        x = math.floor(60 * _G.density_scale), y = math.floor(10 * _G.density_scale),
        w = math.floor(150 * _G.density_scale), h = math.floor(40 * _G.density_scale),
        text = "IOT账号",
        font_size = math.floor(32 * _G.density_scale),
        color = COLOR_WHITE,
        align = airui.TEXT_ALIGN_LEFT
    })

    kv = airui.keyboard({
        x = 0, y = -math.floor(sh * 0.03),
        w = sw, h = math.floor(sh * 0.32),
        mode = "text",
        auto_hide = true,
        on_commit = function(self) self:hide() end
    })

    rbct(nil)
    sys.publish("IOT_GET_ACCOUNT_INFO")
end

local function oc()
    cui()
    sys.subscribe("IOT_LOGIN_RESULT", on_login_resp)
    sys.subscribe("IOT_LOGOUT_RESULT", on_logout_resp)
    sys.subscribe("IOT_ACCOUNT_INFO", up_info)
end

local function od()
    sys.unsubscribe("IOT_LOGIN_RESULT", on_login_resp)
    sys.unsubscribe("IOT_LOGOUT_RESULT", on_logout_resp)
    sys.unsubscribe("IOT_ACCOUNT_INFO", up_info)
    if ct then ct:destroy(); ct = nil end
    if mc then mc:destroy(); mc = nil end
    kv = nil
end

local function ogf() end
local function olf() end

local function oh()
    wid = exwin.open({
        on_create = oc,
        on_destroy = od,
        on_lose_focus = olf,
        on_get_focus = ogf,
    })
end

sys.subscribe("OPEN_IOT_WIN", oh)
