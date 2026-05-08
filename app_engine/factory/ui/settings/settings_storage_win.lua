--[[
@naming  us_s=update_screen_size fm=format_memory fmf=format_memory_full cp=calc_percent ci_r=create_info_row cm_c=create_memory_card c_ui=create_ui | wid=win_id mc=main_container sw=screen_w sh=screen_h m=margin cw=card_w tid=timer_id tl/ul/fl/pb/pl=total/used/free/progress_bar/percent_label stl/sul/sml/spl/spb=sys_* vtl/vul/vml/vpl/vpb=vm_* ptl/pul/pml/ppl/ppb=psram_* sch=STORAGE_CARD_H mch=MEMORY_CARD_H
@module  settings_storage_win
@summary 存储页面
@version 1.2
@date    2026.04.16
@author  江访
]]

local wid = nil
local mc
local tl, ul, fl, pb, pl
local stl, sul, sml, spl, spb
local vtl, vul, vml, vpl, vpb
local ptl, pul, pml, ppl, ppb
local sw, sh = 480, 800
local m = 20
local cw = 440
local tid = nil

local COLOR_PRIMARY        = 0x007AFF
local COLOR_BG             = 0xF5F5F5
local COLOR_CARD           = 0xFFFFFF
local COLOR_TEXT           = 0x333333
local COLOR_TEXT_SECONDARY = 0x757575
local COLOR_DIVIDER        = 0xE0E0E0
local COLOR_WHITE          = 0xFFFFFF
local COLOR_ACCENT         = 0xFF9800

local sch
local mch

local function us_s()
    local rot = airui.get_rotation()
    local pw, ph = lcd.getSize()
    if rot == 0 or rot == 180 then
        sw, sh = pw, ph
    else
        sw, sh = ph, pw
    end
    m = math.floor(sw * 0.04)
    cw = sw - 2 * m
end

local function update_storage_info(inf)
    if tl then tl:set_text(inf.total or "--") end
    if ul then ul:set_text(inf.used or "--") end
    if fl then fl:set_text(inf.free or "--") end
    if inf.used_percent and pb then
        pb:set_value(inf.used_percent, true)
    end
    if inf.used_percent and pl then
        pl:set_text("已使用 " .. inf.used_percent .. "%")
    end
end

local function fm(bs)
    if not bs or bs == 0 then return "0 B" end
    if bs < 1024 then return string.format("%d B", bs)
    elseif bs < 1024*1024 then return string.format("%.2f KB", bs/1024)
    elseif bs < 1024*1024*1024 then return string.format("%.2f MB", bs/1024/1024)
    else return string.format("%.2f GB", bs/1024/1024/1024) end
end

local function fmf(bs)
    if not bs or bs == 0 then return "0 B" end
    local cvt = fm(bs)
    if bs >= 1024 then
        return string.format("%d B (≈%s)", bs, cvt)
    else
        return string.format("%d B", bs)
    end
end

local function cp(u, tt)
    if not u or not tt or tt == 0 then return 0 end
    return math.min(100, math.max(0, (u / tt) * 100))
end

local function update_memory_info(inf)
    if inf.sys and stl then
        local pct = cp(inf.sys.used, inf.sys.total)
        stl:set_text(fm(inf.sys.total))
        sul:set_text(fm(inf.sys.used))
        sml:set_text(fm(inf.sys.max))
        spl:set_text(string.format("%.1f%% 占用", pct))
        if spb then spb:set_value(math.floor(pct), false) end
    end
    if inf.vm and vtl then
        local pct = cp(inf.vm.used, inf.vm.total)
        vtl:set_text(fm(inf.vm.total))
        vul:set_text(fm(inf.vm.used))
        vml:set_text(fm(inf.vm.max))
        vpl:set_text(string.format("%.1f%% 占用", pct))
        if vpb then vpb:set_value(math.floor(pct), false) end
    end
    if inf.psram and ptl then
        local pct = cp(inf.psram.used, inf.psram.total)
        ptl:set_text(fm(inf.psram.total))
        pul:set_text(fm(inf.psram.used))
        pml:set_text(fm(inf.psram.max))
        ppl:set_text(string.format("%.1f%% 占用", pct))
        if ppb then ppb:set_value(math.floor(pct), false) end
    end
end

local function ci_r(p, y, lt)
    local r = airui.container({
        parent = p,
        x = math.floor(20 * _G.density_scale), y = y,
        w = cw - math.floor(40 * _G.density_scale),
        h = math.floor(35 * _G.density_scale),
        color = COLOR_CARD
    })
    airui.label({
        parent = r,
        x = 0, y = math.floor(5 * _G.density_scale),
        w = math.floor(100 * _G.density_scale), h = math.floor(25 * _G.density_scale),
        text = lt,
        font_size = math.floor(16 * _G.density_scale),
        color = COLOR_TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_LEFT
    })
    local vl = airui.label({
        parent = r,
        x = math.floor(110 * _G.density_scale), y = math.floor(5 * _G.density_scale),
        w = (cw - math.floor(40 * _G.density_scale)) - math.floor(110 * _G.density_scale),
        h = math.floor(25 * _G.density_scale),
        text = "--",
        font_size = math.floor(16 * _G.density_scale),
        color = COLOR_TEXT,
        align = airui.TEXT_ALIGN_RIGHT
    })
    return vl
end

local function cm_c(p, y, ti, pcl, ch)
    local cd = airui.container({
        parent = p,
        x = m, y = y,
        w = cw, h = ch,
        color = COLOR_WHITE,
        radius = 8
    })
    local mpd = math.floor(12 * _G.density_scale)
    local mth = math.floor(30 * _G.density_scale)
    local mih = math.floor(35 * _G.density_scale)
    local mbh = math.floor(18 * _G.density_scale)
    local mg = math.floor(4 * _G.density_scale)

    local yt = mpd
    local y1 = yt + mth + mg
    local y2 = y1 + mih + mg
    local y3 = y2 + mih + mg
    local yb = y3 + mih + mg

    airui.label({
        parent = cd,
        x = math.floor(20 * _G.density_scale), y = yt,
        w = math.floor(200 * _G.density_scale), h = mth,
        text = ti,
        font_size = math.floor(22 * _G.density_scale),
        color = COLOR_TEXT,
        align = airui.TEXT_ALIGN_LEFT
    })
    local lpl = airui.label({
        parent = cd,
        x = cw - math.floor(180 * _G.density_scale), y = yt,
        w = math.floor(160 * _G.density_scale), h = mth,
        text = "0% 占用",
        font_size = math.floor(16 * _G.density_scale),
        color = COLOR_PRIMARY,
        align = airui.TEXT_ALIGN_RIGHT
    })
    local ltl = ci_r(cd, y1, "总内存")
    local lul = ci_r(cd, y2, "当前使用")
    local lml = ci_r(cd, y3, "历史峰值")
    local lpb = airui.bar({
        parent = cd,
        x = math.floor(20 * _G.density_scale), y = yb,
        w = cw - math.floor(40 * _G.density_scale),
        h = mbh,
        value = 0,
        bg_color = COLOR_DIVIDER,
        indicator_color = pcl,
        radius = 8
    })
    return {
        total = ltl,
        used = lul,
        max = lml,
        percent = lpl,
        progress = lpb
    }
end

local function c_ui()
    us_s()

    local ch2 = math.floor(sh * 0.20)
    if ch2 < 140 then ch2 = 140 end
    if ch2 > 260 then ch2 = 260 end

    local spd = math.floor(10 * _G.density_scale)
    local srh = math.floor(28 * _G.density_scale)
    local sbh = math.floor(18 * _G.density_scale)
    local ssh = math.floor(22 * _G.density_scale)
    local sg = math.floor(6 * _G.density_scale)
    local yf = spd + srh + sg + sbh + math.floor(2 * _G.density_scale) + ssh + sg + ssh + sg
    local stt = yf + ssh + spd
    sch = math.max(ch2, stt)

    local mpd = math.floor(12 * _G.density_scale)
    local mth = math.floor(30 * _G.density_scale)
    local mih = math.floor(35 * _G.density_scale)
    local mbh = math.floor(18 * _G.density_scale)
    local mg = math.floor(4 * _G.density_scale)
    local yb2 = mpd + mth + mg + mih + mg + mih + mg + mih + mg
    local mtt = yb2 + mbh + mpd + math.floor(8 * _G.density_scale)
    mch = math.max(ch2, mtt)

    mc = airui.container({
        parent = airui.screen,
        x = 0, y = 0,
        w = sw, h = sh,
        color = COLOR_BG
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
        text = "存储",
        font_size = math.floor(32 * _G.density_scale),
        color = COLOR_WHITE,
        align = airui.TEXT_ALIGN_LEFT
    })

    local th2 = math.floor(60 * _G.density_scale)
    local ct = airui.container({
        parent = mc,
        x = 0, y = th2,
        w = sw, h = sh - th2,
        color = COLOR_BG,
        scrollable = true
    })

    local cg = math.floor(m * 0.7)
    local cy = m

    local yt = spd
    local yb3 = yt + srh + sg
    local yp = yb3 + sbh + math.floor(2 * _G.density_scale)
    local yu = yp + ssh + sg
    local yf2 = yu + ssh + sg

    local cs = airui.container({
        parent = ct,
        x = m, y = cy,
        w = cw, h = sch,
        color = COLOR_WHITE,
        radius = 8
    })
    cy = cy + sch + cg

    airui.label({
        parent = cs,
        x = math.floor(20 * _G.density_scale), y = yt,
        w = math.floor(100 * _G.density_scale), h = srh,
        text = "总容量",
        font_size = math.floor(20 * _G.density_scale),
        color = COLOR_TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_LEFT
    })
    tl = airui.label({
        parent = cs,
        x = cw - math.floor(220 * _G.density_scale), y = yt,
        w = math.floor(200 * _G.density_scale), h = srh,
        text = "--",
        font_size = math.floor(22 * _G.density_scale),
        color = COLOR_TEXT,
        align = airui.TEXT_ALIGN_RIGHT
    })

    pb = airui.bar({
        parent = cs,
        x = math.floor(20 * _G.density_scale), y = yb3,
        w = cw - math.floor(40 * _G.density_scale),
        h = sbh,
        min = 0, max = 100,
        value = 0,
        bg_color = COLOR_DIVIDER,
        indicator_color = COLOR_PRIMARY,
        radius = 8
    })

    pl = airui.label({
        parent = cs,
        x = cw - math.floor(220 * _G.density_scale), y = yp,
        w = math.floor(200 * _G.density_scale), h = ssh,
        text = "已使用 --%",
        font_size = math.floor(18 * _G.density_scale),
        color = COLOR_PRIMARY,
        align = airui.TEXT_ALIGN_RIGHT
    })

    airui.label({
        parent = cs,
        x = math.floor(20 * _G.density_scale), y = yu,
        w = math.floor(100 * _G.density_scale), h = ssh,
        text = "已使用",
        font_size = math.floor(18 * _G.density_scale),
        color = COLOR_TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_LEFT
    })
    ul = airui.label({
        parent = cs,
        x = cw - math.floor(220 * _G.density_scale), y = yu,
        w = math.floor(200 * _G.density_scale), h = ssh,
        text = "--",
        font_size = math.floor(20 * _G.density_scale),
        color = COLOR_TEXT,
        align = airui.TEXT_ALIGN_RIGHT
    })

    airui.label({
        parent = cs,
        x = math.floor(20 * _G.density_scale), y = yf2,
        w = math.floor(100 * _G.density_scale), h = ssh,
        text = "可用空间",
        font_size = math.floor(18 * _G.density_scale),
        color = COLOR_TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_LEFT
    })
    fl = airui.label({
        parent = cs,
        x = cw - math.floor(220 * _G.density_scale), y = yf2,
        w = math.floor(200 * _G.density_scale), h = ssh,
        text = "--",
        font_size = math.floor(20 * _G.density_scale),
        color = COLOR_TEXT,
        align = airui.TEXT_ALIGN_RIGHT
    })

    local sy = cm_c(ct, cy, "系统内存", 0x4CAF50, mch)
    stl, sul, sml, spl, spb = sy.total, sy.used, sy.max, sy.percent, sy.progress
    cy = cy + mch + cg

    local vm = cm_c(ct, cy, "Lua 虚拟机内存", COLOR_ACCENT, mch)
    vtl, vul, vml, vpl, vpb = vm.total, vm.used, vm.max, vm.percent, vm.progress
    cy = cy + mch + cg

    local pr = cm_c(ct, cy, "PSRAM 内存", 0x9C27B0, mch)
    ptl, pul, pml, ppl, ppb = pr.total, pr.used, pr.max, pr.percent, pr.progress

end

local function on_create()
    c_ui()
    sys.publish("STORAGE_GET_INFO")
    sys.publish("MEMORY_INFO_GET")
    if tid then sys.timerStop(tid) end
    tid = sys.timerLoopStart(function()
        sys.publish("MEMORY_INFO_GET")
    end, 1000)
end

local function on_destroy()
    if tid then sys.timerStop(tid); tid = nil end
    if mc then mc:destroy(); mc = nil end
    tl = nil; ul = nil; fl = nil; pb = nil; pl = nil
    stl = nil; sul = nil; sml = nil; spl = nil; spb = nil
    vtl = nil; vul = nil; vml = nil; vpl = nil; vpb = nil
    ptl = nil; pul = nil; pml = nil; ppl = nil; ppb = nil
end

local function on_get_focus() end
local function on_lose_focus() end

local function open_handler()
    wid = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_lose_focus = on_lose_focus,
        on_get_focus = on_get_focus,
    })
end

sys.subscribe("STORAGE_INFO", update_storage_info)
sys.subscribe("MEMORY_INFO", update_memory_info)
sys.subscribe("OPEN_STORAGE_WIN", open_handler)
