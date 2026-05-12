--[[
@naming  us_s=update_screen_size cc_r=create_clickable_row ci_r=create_info_row ce_w=create_edit_win c_ui=create_ui | wid=win_id mc=main_container dnl=device_name_label mdl=model_label uil=unique_id_label uhl=unique_id_hex_label vsl=version_label knl=kernel_label ew=edit_win ni=name_input kb=keyboard sw=screen_w sh=screen_h m=margin cw=card_w pn=product_name
@module  settings_about_win
@summary 关于设备子页面
@version 1.2 (自适应分辨率，移除内存信息)
@date    2026.04.16
@author  江访
]]

local wid = nil
local mc
local dnl
local mdl
local uil
local uhl
local vsl
local knl
local ew = nil
local ni
local kb

local sw, sh = 480, 800
local m = 15
local cw = 460

local COLOR_PRIMARY        = 0x007AFF
local COLOR_PRIMARY_DARK   = 0x0056B3
local COLOR_BG             = 0xF5F5F5
local COLOR_CARD           = 0xFFFFFF
local COLOR_TEXT           = 0x333333
local COLOR_TEXT_SECONDARY = 0x757575
local COLOR_DIVIDER        = 0xE0E0E0
local COLOR_WHITE          = 0xFFFFFF

local pn = "合宙引擎主机"

local function us_s()
    local rot = airui.get_rotation()
    local pw, ph = lcd.getSize()
    if rot == 0 or rot == 180 then
        sw, sh = pw, ph
    else
        sw, sh = ph, pw
    end
    m = math.floor(sw * 0.03)
    cw = sw - 2 * m
end

local function update_device_info(inf)
    if dnl and inf.device_name then
        dnl:set_text(inf.device_name)
    end
    if mdl and inf.model then
        mdl:set_text(inf.model)
    end
    if uil and inf.unique_id then
        uil:set_text(inf.unique_id)
    end
    if uhl and inf.unique_id_hex then
        uhl:set_text(inf.unique_id_hex)
    end
    if vsl and inf.version then
        vsl:set_text(inf.version)
    end
    if knl and inf.kernel then
        knl:set_text(inf.kernel)
    end
    log.info("s_abt", "UI更新设备信息")
end

local function udi(inf) update_device_info(inf) end

local function udn(dn)
    if dnl then
        dnl:set_text(dn)
        log.info("s_abt", "更新设备名称", dn)
    end
end

local function cc_r(p, y, lt, oc)
    local r = airui.container({
        parent = p,
        x = 0, y = y,
        w = cw,
        h = math.floor(50 * _G.density_scale),
        color = COLOR_WHITE,
        on_click = oc
    })
    airui.label({
        parent = r,
        x = math.floor(20 * _G.density_scale), y = math.floor(10 * _G.density_scale),
        w = math.floor(150 * _G.density_scale), h = math.floor(30 * _G.density_scale),
        text = lt,
        font_size = math.floor(22 * _G.density_scale),
        color = COLOR_TEXT,
        align = airui.TEXT_ALIGN_LEFT
    })
    airui.label({
        parent = r,
        x = cw - math.floor(60 * _G.density_scale), y = math.floor(10 * _G.density_scale),
        w = math.floor(40 * _G.density_scale), h = math.floor(30 * _G.density_scale),
        text = ">",
        font_size = math.floor(22 * _G.density_scale),
        color = COLOR_TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_RIGHT
    })
    return r
end

local function ci_r(p, y, lt, vt)
    local ik = (lt == "内核版本")
    local rh = math.floor((ik and 120 or 70) * _G.density_scale)
    local vw = cw - math.floor(150 * _G.density_scale) - math.floor(30 * _G.density_scale)
    local vh = math.floor((ik and 100 or 50) * _G.density_scale)

    local r = airui.container({
        parent = p,
        x = 0, y = y,
        w = cw,
        h = rh,
        color = COLOR_CARD
    })
    airui.label({
        parent = r,
        x = math.floor(20 * _G.density_scale), y = math.floor(10 * _G.density_scale),
        w = math.floor(150 * _G.density_scale), h = math.floor(30 * _G.density_scale),
        text = lt,
        font_size = math.floor(22 * _G.density_scale),
        color = COLOR_TEXT,
        align = airui.TEXT_ALIGN_LEFT
    })
    local vl = airui.label({
        parent = r,
        x = math.floor(180 * _G.density_scale), y = math.floor(10 * _G.density_scale),
        w = vw,
        h = vh,
        text = vt,
        font_size = math.floor(22 * _G.density_scale),
        color = COLOR_TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_RIGHT,
        long_mode = true
    })
    return vl
end

local function ce_w(dn)
    local ww = math.floor(sw * 0.85)
    local wh = math.floor(sh * 0.45)
    local pd = math.floor(20 * _G.density_scale)

    kb = airui.keyboard({
        x = 0, y = -math.floor(20 * _G.density_scale),
        w = sw, h = math.floor(280 * _G.density_scale),
        mode = "text",
        auto_hide = true,
        on_commit = function(self) self:hide() end
    })

    ew = airui.win({
        parent = mc,
        title = "更改设备名称",
        w = ww,
        h = wh,
        close_btn = false,
        auto_center = true,
        style = {
            bg_color = COLOR_CARD,
            header_bg_color = COLOR_PRIMARY,
            content_bg_color = COLOR_CARD,
            title_text_color = COLOR_WHITE,
            radius = 12,
            title_align = airui.TEXT_ALIGN_CENTER,
            header_height = math.floor(50 * _G.density_scale),
        },
        on_close = function(self)
            log.info("s_abt", "编辑窗口已关闭")
            if kb then kb = nil end
            ew = nil
        end
    })

    ni = airui.textarea({
        parent = ew,
        x = pd,
        y = math.floor(60 * _G.density_scale),
        w = ww - 2 * pd - math.floor(40 * _G.density_scale),
        h = math.floor(60 * _G.density_scale),
        text = dn or "",
        placeholder = "请输入设备名称",
        max_len = 32,
        font_size = math.floor(20 * _G.density_scale),
        keyboard = kb
    })

    local bw = math.floor(math.min(math.floor(120 * _G.density_scale), (ww - 3 * pd) / 2))
    local bx1 = pd + math.floor(20 * _G.density_scale)
    local bx2 = ww - pd - math.floor(20 * _G.density_scale) - bw

    airui.button({
        parent = ew,
        x = bx1, y = math.floor(150 * _G.density_scale),
        w = bw, h = math.floor(50 * _G.density_scale),
        text = "返回",
        font_size = math.floor(20 * _G.density_scale),
        style = {
            bg_color = COLOR_DIVIDER,
            pressed_bg_color = COLOR_DIVIDER,
            text_color = COLOR_TEXT,
            radius = 8,
            border_width = 1,
            border_color = COLOR_DIVIDER
        },
        on_click = function()
            if ew then ew:close() end
        end
    })
    airui.button({
        parent = ew,
        x = bx2, y = math.floor(150 * _G.density_scale),
        w = bw, h = math.floor(50 * _G.density_scale),
        text = "保存",
        font_size = math.floor(20 * _G.density_scale),
        style = {
            bg_color = COLOR_PRIMARY,
            pressed_bg_color = COLOR_PRIMARY_DARK,
            text_color = COLOR_WHITE,
            radius = 8,
            border_width = 0
        },
        on_click = function()
            local nm = ni:get_text()
            if nm and #nm > 0 then
                if dnl then
                    dnl:set_text(nm)
                end
                sys.publish("CONFIG_SET_DEVICE_NAME", nm)
                airui.msgbox({
                    title = "提示",
                    text = "设备名称已保存",
                    buttons = {"确定"},
                    on_action = function(self)
                        self:hide()
                        if ew then ew:close() end
                    end
                })
            else
                airui.msgbox({
                    title = "提示",
                    text = "设备名称不能为空",
                    buttons = {"确定"},
                    on_action = function(self) self:hide() end
                })
            end
        end
    })
end

local function c_ui()
    us_s()

    local sf = _G.model_str:gsub("^Air", "")
    if sf ~= "" then
        pn = "合宙引擎主机" .. sf
    end

    mc = airui.container({
        x = 0, y = 0,
        w = sw, h = sh,
        color = COLOR_BG,
        parent = airui.screen
    })

    local tb = airui.container({
        parent = mc,
        x = 0, y = 0,
        w = sw, h = math.floor(60 * _G.density_scale),
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
        w = math.floor(200 * _G.density_scale), h = math.floor(40 * _G.density_scale),
        text = "关于设备",
        font_size = math.floor(32 * _G.density_scale),
        color = COLOR_WHITE,
        align = airui.TEXT_ALIGN_LEFT
    })

    local th = math.floor(60 * _G.density_scale)
    local ct = airui.container({
        parent = mc,
        x = 0, y = th,
        w = sw, h = sh - th,
        color = COLOR_BG,
        scrollable = true,
    })

    local cdn = airui.container({
        parent = ct,
        x = m, y = math.floor(20 * _G.density_scale),
        w = cw, h = math.floor(70 * _G.density_scale),
        color = COLOR_WHITE,
        radius = 8
    })
    cc_r(cdn, math.floor(10 * _G.density_scale), "设备名称", function()
        local cn = dnl and dnl:get_text() or ""
        ce_w(cn)
    end)
    dnl = airui.label({
        parent = cdn,
        x = math.floor(90 * _G.density_scale), y = math.floor(20 * _G.density_scale),
        w = cw - math.floor(130 * _G.density_scale), h = math.floor(30 * _G.density_scale),
        text = pn,
        font_size = math.floor(22 * _G.density_scale),
        color = COLOR_TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_RIGHT
    })

    local ci = airui.container({
        parent = ct,
        x = m, y = math.floor(110 * _G.density_scale),
        w = cw, h = math.floor(380 * _G.density_scale),
        color = COLOR_WHITE,
        radius = 8
    })
    mdl = ci_r(ci, math.floor(10 * _G.density_scale), "设备型号", "--")
    uil = ci_r(ci, math.floor(70 * _G.density_scale), "设备 ID", "--")
    uhl = ci_r(ci, math.floor(130 * _G.density_scale), "设备 ID (HEX)", "--")
    vsl = ci_r(ci, math.floor(190 * _G.density_scale), "软件版本", "--")
    knl = ci_r(ci, math.floor(250 * _G.density_scale), "内核版本", "--")
end

local function on_create()
    c_ui()
    sys.publish("ABOUT_DEVICE_GET_INFO")
    sys.publish("CONFIG_GET_DEVICE_NAME")
    sys.subscribe("ABOUT_DEVICE_INFO", udi)
    sys.subscribe("CONFIG_DEVICE_NAME_VALUE", udn)
end

local function on_destroy()
    sys.unsubscribe("ABOUT_DEVICE_INFO", udi)
    sys.unsubscribe("CONFIG_DEVICE_NAME_VALUE", udn)
    if mc then
        mc:destroy()
        mc = nil
    end
    dnl = nil
    mdl = nil
    uil = nil
    uhl = nil
    vsl = nil
    knl = nil
end

local function on_get_focus() end
local function on_lose_focus()
    if ew then ew:close() end
end

local function open_handler()
    wid = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_lose_focus = on_lose_focus,
        on_get_focus = on_get_focus,
    })
end

sys.subscribe("OPEN_ABOUT_WIN", open_handler)
