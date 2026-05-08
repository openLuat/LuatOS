--[[
@module  speedtest_win
@summary 网络测速窗口模块（UI层）
@version 1.0.0
@date    2026.04.28
@author  江访
-- 命名约定：局部函数名2-5字符(fn),局部变量名2-4字符(vr),公开API和全局常量保持原名
]]

local wid = nil
local mc = nil

local dl = nil
local ul = nil
local pl = nil
local jl = nil
local sl = nil
local sb = nil
local dul = nil
local uul = nil

local sw, sh = 480, 800
local mg = 15
local th = 60

local COLOR_PRIMARY        = 0x007AFF
local COLOR_PRIMARY_DARK   = 0x0056B3
local COLOR_BG             = 0xF5F5F5
local COLOR_CARD           = 0xFFFFFF
local COLOR_TEXT           = 0x333333
local COLOR_TEXT_SECONDARY = 0x757575
local COLOR_DIVIDER        = 0xE0E0E0
local COLOR_WHITE          = 0xFFFFFF
local COLOR_DANGER         = 0xE63946

local function uss()
    local rt = airui.get_rotation()
    local pw, ph = lcd.getSize()
    if rt == 0 or rt == 180 then
        sw, sh = pw, ph
    else
        sw, sh = ph, pw
    end
    mg = math.floor(sw * 0.03)
    th = 60
end

local function fs(v)
    if v == nil then return "--" end
    local kb = v * 1000
    if kb >= 1000 then
        return string.format("%.1f", kb / 1000)
    else
        return string.format("%d", math.floor(kb))
    end
end

local function gsu(v)
    if v == nil then return "Kbps" end
    local kb = v * 1000
    if kb >= 1000 then
        return "Mbps"
    else
        return "Kbps"
    end
end

local function fl(v)
    if v == nil then return "--" end
    return string.format("%d", math.floor(v))
end

local function rd()
    if dl then dl:set_text("--") end
    if ul then ul:set_text("--") end
    if pl then pl:set_text("--") end
    if jl then jl:set_text("--") end
    if sl then sl:set_text("就绪") end
end

local function cui()
    uss()
    mc = airui.container({
        parent = airui.screen,
        x = 0, y = 0,
        w = sw, h = sh,
        color = COLOR_CARD,
        scrollable = true,
    })

    local tb = airui.container({
        parent = mc,
        x = 0, y = 0,
        w = sw, h = math.floor(th * _G.density_scale),
        color = COLOR_PRIMARY
    })
    local bb = airui.container({
        parent = tb,
        x = math.floor(10 * _G.density_scale), y = math.floor(10 * _G.density_scale),
        w = math.floor(50 * _G.density_scale), h = math.floor(40 * _G.density_scale),
        color = COLOR_PRIMARY,
        on_click = function()
            if wid then exwin.close(wid) end
        end
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
        w = math.floor(140 * _G.density_scale), h = math.floor(40 * _G.density_scale),
        text = "网络测速",
        font_size = math.floor(32 * _G.density_scale),
        color = COLOR_WHITE,
        align = airui.TEXT_ALIGN_LEFT
    })

    local cy = math.floor((th + 10) * _G.density_scale)
    local ch = sh - cy

    local cw = math.floor((sw - mg * 3) / 2)
    local cah = math.min(math.floor(ch * 0.35), math.floor(250 * _G.density_scale))

    local aw = cw
    local ah = math.floor(cah * 0.65)

    local bw = math.floor(sw * 0.65)
    local bh = math.floor(math.min(math.floor(60 * _G.density_scale), math.floor(sh * 0.075 * _G.density_scale)))

    local cay = cy
    local cg = mg

    local dc = airui.container({
        parent = mc,
        x = mg,
        y = cay,
        w = cw,
        h = cah,
        color = COLOR_CARD,
        radius = 48
    })
    local isz = math.floor(math.min(math.floor(40 * _G.density_scale), math.floor(cw * 0.19 * _G.density_scale)))
    local iy = math.floor(cah * 0.08)
    airui.label({
        parent = dc,
        x = 0,
        y = iy + isz + math.floor(5 * _G.density_scale),
        w = cw,
        h = math.floor(cah * 0.12),
        text = "下载速度",
        font_size = math.floor(cah * 0.09 * _G.density_scale),
        color = COLOR_TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_CENTER
    })
    dl = airui.label({
        parent = dc,
        x = 0,
        y = math.floor(cah * 0.45),
        w = cw,
        h = math.floor(cah * 0.28),
        text = "--",
        font_size = math.min(math.floor(cah * 0.3), math.floor(60 * _G.density_scale)),
        color = COLOR_PRIMARY,
        align = airui.TEXT_ALIGN_CENTER
    })
    dul = airui.label({
        parent = dc,
        x = 0,
        y = math.floor(cah * 0.78),
        w = cw,
        h = math.floor(cah * 0.12),
        text = "Kbps",
        font_size = math.min(math.floor(cah * 0.09), math.floor(20 * _G.density_scale)),
        color = COLOR_TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_CENTER
    })

    local uc = airui.container({
        parent = mc,
        x = mg + cw + cg,
        y = cay,
        w = cw,
        h = cah,
        color = COLOR_CARD,
        radius = 48
    })
    airui.label({
        parent = uc,
        x = 0,
        y = iy + isz + math.floor(5 * _G.density_scale),
        w = cw,
        h = math.floor(cah * 0.12),
        text = "上传速度",
        font_size = math.floor(cah * 0.09 * _G.density_scale),
        color = COLOR_TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_CENTER
    })
    ul = airui.label({
        parent = uc,
        x = 0,
        y = math.floor(cah * 0.45),
        w = cw,
        h = math.floor(cah * 0.28),
        text = "--",
        font_size = math.min(math.floor(cah * 0.3), math.floor(60 * _G.density_scale)),
        color = COLOR_DANGER,
        align = airui.TEXT_ALIGN_CENTER
    })
    uul = airui.label({
        parent = uc,
        x = 0,
        y = math.floor(cah * 0.78),
        w = cw,
        h = math.floor(cah * 0.12),
        text = "Kbps",
        font_size = math.min(math.floor(cah * 0.09), math.floor(20 * _G.density_scale)),
        color = COLOR_TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_CENTER
    })

    local ay = cay + cah + mg
    local pc = airui.container({
        parent = mc,
        x = mg,
        y = ay,
        w = aw,
        h = ah,
        color = COLOR_CARD,
        radius = 36
    })
    airui.label({
        parent = pc,
        x = 0,
        y = math.floor(ah * 0.12),
        w = aw,
        h = math.floor(ah * 0.16),
        text = "延迟 (Ping)",
        font_size = math.floor(ah * 0.11 * _G.density_scale),
        color = COLOR_TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_CENTER
    })
    pl = airui.label({
        parent = pc,
        x = 0,
        y = math.floor(ah * 0.34),
        w = aw,
        h = math.floor(ah * 0.32),
        text = "--",
        font_size = math.floor(ah * 0.24 * _G.density_scale),
        color = COLOR_TEXT,
        align = airui.TEXT_ALIGN_CENTER
    })
    airui.label({
        parent = pc,
        x = 0,
        y = math.floor(ah * 0.76),
        w = aw,
        h = math.floor(ah * 0.16),
        text = "ms",
        font_size = math.floor(ah * 0.12 * _G.density_scale),
        color = COLOR_TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_CENTER
    })

    local jc = airui.container({
        parent = mc,
        x = mg + cw + cg,
        y = ay,
        w = aw,
        h = ah,
        color = COLOR_CARD,
        radius = 36
    })
    airui.label({
        parent = jc,
        x = 0,
        y = math.floor(ah * 0.12),
        w = aw,
        h = math.floor(ah * 0.16),
        text = "抖动 (Jitter)",
        font_size = math.floor(ah * 0.11 * _G.density_scale),
        color = COLOR_TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_CENTER
    })
    jl = airui.label({
        parent = jc,
        x = 0,
        y = math.floor(ah * 0.34),
        w = aw,
        h = math.floor(ah * 0.32),
        text = "--",
        font_size = math.floor(ah * 0.24 * _G.density_scale),
        color = COLOR_TEXT,
        align = airui.TEXT_ALIGN_CENTER
    })
    airui.label({
        parent = jc,
        x = 0,
        y = math.floor(ah * 0.76),
        w = aw,
        h = math.floor(ah * 0.16),
        text = "ms",
        font_size = math.floor(ah * 0.12 * _G.density_scale),
        color = COLOR_TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_CENTER
    })

    local by = ay + ah + mg
    sb = airui.button({
        parent = mc,
        x = math.floor((sw - bw) / 2),
        y = by,
        w = bw,
        h = bh,
        text = "开始测速",
        font_size = math.floor(bh * 0.35 * _G.density_scale),
        font_color = COLOR_WHITE,
        bg_color = COLOR_PRIMARY,
        radius = bh / 2,
        on_click = function()
            sys.publish("SPEEDTEST_START")
        end
    })

    local sy = by + bh + math.floor(mg * 1.5)
    sl = airui.label({
        parent = mc,
        x = 0,
        y = sy,
        w = sw,
        h = math.floor(sh * 0.04),
        text = "就绪",
        font_size = math.floor(sh * 0.022 * _G.density_scale),
        color = COLOR_TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_CENTER
    })
end

local function onss()
    if sb then
        sb:set_text("测速中...")
        sb:set_style({ bg_color = COLOR_TEXT_SECONDARY, text_color = COLOR_WHITE })
    end
    rd()
end

local function onsr(rs)
    if rs.ping then
        if pl then pl:set_text(fl(rs.ping)) end
    else
        if pl then pl:set_text("ERR") end
    end
    if rs.jitter then
        if jl then jl:set_text(string.format("%.1f", rs.jitter)) end
    else
        if jl then jl:set_text("ERR") end
    end
    if rs.download then
        if dl then dl:set_text(fs(rs.download)) end
        if dul then dul:set_text(gsu(rs.download)) end
    else
        if dl then dl:set_text("失败") end
        if dul then dul:set_text("") end
    end
    if rs.upload then
        if ul then ul:set_text(fs(rs.upload)) end
        if uul then uul:set_text(gsu(rs.upload)) end
    else
        if ul then ul:set_text("失败") end
        if uul then uul:set_text("") end
    end
end

local function onst(st)
    if sl then sl:set_text(st) end
end

local function onsf()
    if sb then
        sb:set_text("重新测速")
        sb:set_style({ bg_color = COLOR_PRIMARY_DARK, text_color = COLOR_WHITE })
    end
end

local function onc()
    cui()
end

local function ond()
    if mc then
        mc:destroy()
        mc = nil
    end
    -- 将组件引用置nil，避免测速回调中操作已销毁的UI对象导致死机
    dl = nil
    ul = nil
    pl = nil
    jl = nil
    sl = nil
    sb = nil
    dul = nil
    uul = nil
    wid = nil
end

local function ongf() end

local function onlf() end

local function oph()
    wid = exwin.open({
        on_create = onc,
        on_destroy = ond,
        on_get_focus = ongf,
        on_lose_focus = onlf,
    })
end

sys.subscribe("OPEN_SPEEDTEST_WIN", oph)
sys.subscribe("SPDTEST_STARTED", onss)
sys.subscribe("SPDTEST_RESULT", onsr)
sys.subscribe("SPDTEST_STATUS", onst)
sys.subscribe("SPDTEST_FINISHED", onsf)
