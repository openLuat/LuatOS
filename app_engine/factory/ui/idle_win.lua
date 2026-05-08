--[[
@module  idle_win
@summary 首页窗口模块，融合主菜单功能，采用选项卡滑动切换
@version 1.4
@date    2026.04.28
@author  江访
]]

-- Abbreviations: cl=calc_layout, upi=update_page_indicator, bhp=build_home_page,
-- bgp=build_app_grid_page, rap=refresh_app_pages, lea=load_external_apps,
-- utd=update_time_date, uwi=update_wifi_icon, umi=update_mobile_icon,
-- ost,osw,osm=on_status_*, oc=on_create, od=on_destroy, oh=open_handler,
-- tv=tabview, mc=main_container, sc=status_cache, ba=builtin_apps, ct=current_tab_index,
-- th=top_h, pih=page_indicator_h, cw=card_w, ch=card_h, ap=apps_per_page

local wid = nil
local mc = nil
local pl, btl, dl, wi, mi, qr
local pgl = nil
local tv = nil
local ct = 0

local sc = { time = "08:00", date = "1970-01-01", weekday = "星期四", mobile_level = -1, wifi_level = 0 }

local ba = {
    { name = "设置", win = "SETTINGS", icon = "/luadb/settings.png" },
    { name = "应用市场", win = "APP_STORE", icon = "/luadb/app_store_icon.png" },
    { name = "网络测速", win = "SPEEDTEST", icon = "/luadb/internet_speed.png" },
}

local th = 60
local pih = 40
local cw, ch = 0, 0
local gcs = 1
local ap = 0
local gm = 8
local gtp = 16

local btfs = math.floor(100 * _G.density_scale)
local bty = 20
local dy = 130
local dfs = math.floor(20 * _G.density_scale)
local qs = math.floor(130 * _G.density_scale)
local qy = 190
local by = 0
local bbw = math.floor(80 * _G.density_scale)
local bbs = math.floor(20 * _G.density_scale)

local tt = nil
local eac = {}
local pg = {}

local COLOR_PRIMARY        = 0x007AFF
local COLOR_PRIMARY_DARK   = 0x0056B3
local COLOR_ACCENT         = 0xFF9800
local COLOR_BG             = 0xF5F5F5
local COLOR_CARD           = 0xFFFFFF
local COLOR_TEXT           = 0x333333
local COLOR_TEXT_SECONDARY = 0x757575
local COLOR_DIVIDER        = 0xE0E0E0
local COLOR_WHITE          = 0xFFFFFF
local COLOR_DANGER         = 0xE63946

local pn = "合宙引擎主机"
local ia8 = _G.model_str:find("Air8000") ~= nil
local sf = _G.model_str:gsub("^Air", "")
if sf ~= "" then
    pn = "合宙引擎主机" .. sf
end

local function cl()
    if is_landscape then
        th = math.max(44, math.min(70, math.floor(44 * screen_h / 480)))
        pih = math.max(28, math.min(50, math.floor(28 * screen_h / 480)))
    else
        th = math.max(44, math.min(70, math.floor(59 * screen_h / 854)))
        pih = math.max(28, math.min(50, math.floor(29 * screen_h / 854)))
    end

    local cm = is_landscape and screen_h < 400
    if cm then
        btfs = 0
        bty = 0
        dfs = math.max(math.floor(14 * _G.density_scale), math.min(math.floor(18 * _G.density_scale), math.floor(screen_h * 0.03 * _G.density_scale)))
        dy = math.floor(screen_h * 0.01)
        qs = math.max(math.floor(45 * _G.density_scale), math.min(math.floor(70 * _G.density_scale), math.floor(screen_h * 0.20 * _G.density_scale)))
        qy = dy + dfs + math.floor(4 * _G.density_scale)
        bbw = math.max(math.floor(45 * _G.density_scale), math.min(math.floor(65 * _G.density_scale), math.floor(screen_w * 0.055 * _G.density_scale)))
        bbs = math.max(math.floor(4 * _G.density_scale), math.min(math.floor(10 * _G.density_scale), math.floor(screen_w * 0.01 * _G.density_scale)))
    elseif is_landscape then
        btfs = math.max(math.floor(40 * _G.density_scale), math.min(math.floor(80 * _G.density_scale), math.floor(screen_h * 0.15 * _G.density_scale)))
        bty = math.floor(screen_h * 0.015)
        dfs = math.max(math.floor(14 * _G.density_scale), math.min(math.floor(18 * _G.density_scale), math.floor(screen_h * 0.03 * _G.density_scale)))
        dy = bty + btfs + math.floor(8 * _G.density_scale)
        qs = math.max(math.floor(50 * _G.density_scale), math.min(math.floor(110 * _G.density_scale), math.floor(screen_h * 0.20 * _G.density_scale)))
        qy = dy + dfs + math.floor(10 * _G.density_scale)
        bbw = math.max(math.floor(55 * _G.density_scale), math.min(math.floor(75 * _G.density_scale), math.floor(screen_w * 0.065 * _G.density_scale)))
        bbs = math.max(math.floor(6 * _G.density_scale), math.min(math.floor(16 * _G.density_scale), math.floor(screen_w * 0.012 * _G.density_scale)))
    else
        btfs = math.max(math.floor(48 * _G.density_scale), math.min(math.floor(130 * _G.density_scale), math.floor(screen_h * 0.10 * _G.density_scale)))
        bty = math.floor(screen_h * 0.025)
        dfs = math.max(math.floor(14 * _G.density_scale), math.min(math.floor(22 * _G.density_scale), math.floor(screen_h * 0.028 * _G.density_scale)))
        dy = bty + btfs + math.floor(15 * _G.density_scale)
        qs = math.max(math.floor(60 * _G.density_scale), math.min(math.floor(150 * _G.density_scale), math.floor(screen_w * 0.25 * _G.density_scale)))
        qy = dy + dfs + math.floor(18 * _G.density_scale)
        bbw = math.max(math.floor(60 * _G.density_scale), math.min(math.floor(90 * _G.density_scale), math.floor(screen_w * 0.16 * _G.density_scale)))
        bbs = math.max(math.floor(8 * _G.density_scale), math.min(math.floor(30 * _G.density_scale), math.floor(screen_w * 0.035 * _G.density_scale)))
    end

    by = qy + qs + math.floor(55 * _G.density_scale)

    local isz = math.floor(32 * _G.density_scale)
    local bf = math.floor(screen_h / 32 * _G.density_scale)
    local tfs = math.max(math.floor(14 * _G.density_scale), math.min(math.floor(18 * _G.density_scale), bf))

    local gaw = screen_w
    local gah = screen_h - th - pih

    local mcw = is_landscape and 120 or 100
    gcs = math.max(1, math.floor(gaw / mcw))
    local mxc = math.floor(gaw / 70)
    if gcs > mxc then gcs = mxc end
    gcs = math.min(gcs, 8)

    cw = math.floor((gaw - (gcs + 1) * gm) / gcs)

    local txh = tfs * 2 + 8
    local pv = is_landscape and 12 or 16
    ch = isz + txh + pv
    if ch < math.floor(70 * _G.density_scale) then ch = math.floor(70 * _G.density_scale) end

    local ah = gah - gtp
    local rpp = math.max(1, math.floor(ah / (ch + gm)))
    ap = gcs * rpp

end

local function upi()
    if not tv or not pgl then return end
    local total = tv:get_tab_count()
    pgl:set_text(string.format("%d/%d", ct + 1, total))
end

local function bhp(page_container)
    local ctn = airui.container({
        parent = page_container,
        x = 0, y = 0, w = screen_w, h = screen_h - th - pih,
        color = COLOR_BG
    })

    if btfs > 0 then
        btl = airui.label({
            parent = ctn,
            x = 0, y = bty, w = screen_w, h = btfs + 10,
            text = "08:00", font_size = btfs, color = COLOR_TEXT,
            align = airui.TEXT_ALIGN_CENTER
        })
    else
        btl = nil
    end

    dl = airui.label({
        parent = ctn,
        x = 0, y = dy, w = screen_w, h = dfs + 20,
        text = "1970-01-01 星期四", font_size = dfs,
        color = COLOR_TEXT_SECONDARY, align = airui.TEXT_ALIGN_CENTER
    })

    local qcx = (screen_w - qs) / 2
    qr = airui.qrcode({
        parent = ctn, x = qcx, y = qy, size = qs,
        data = "https://docs.openluat.com/",
        dark_color = 0x000000, light_color = COLOR_WHITE, quiet_zone = true
    })
    airui.label({
        parent = ctn,
        x = 0, y = qy + qs + math.floor(5 * _G.density_scale),
        w = screen_w, h = math.floor(22 * _G.density_scale),
        text = "资料中心", font_size = math.floor(14 * _G.density_scale),
        color = COLOR_TEXT, align = airui.TEXT_ALIGN_CENTER
    })

    local bsx = (screen_w - (bbw * #ba + bbs * (#ba - 1))) / 2

    for i, app in ipairs(ba) do
        local x = bsx + (i - 1) * (bbw + bbs)
        local c = airui.container({
            parent = ctn, x = x, y = by, w = bbw,
            h = math.floor(100 * _G.density_scale), color = COLOR_BG,
            on_click = function() sys.publish("OPEN_" .. app.win .. "_WIN") end
        })
        local bis = math.min(math.floor(40 * _G.density_scale), bbw - math.floor(10 * _G.density_scale))
        local bix = (bbw - bis) / 2
        airui.image({
            parent = c, x = bix, y = math.floor(10 * _G.density_scale),
            w = bis, h = bis, src = app.icon
        })
        airui.label({
            parent = c, x = 0,
            y = bis + math.floor(18 * _G.density_scale),
            w = bbw, h = math.floor(30 * _G.density_scale),
            text = app.name, font_size = math.floor(14 * _G.density_scale),
            color = COLOR_TEXT, align = airui.TEXT_ALIGN_CENTER
        })
    end
end

local function bgp(page_container, start_idx, apps)
    local gcn = airui.container({
        parent = page_container,
        x = 0, y = 0, w = screen_w, h = screen_h - th - pih,
        color = COLOR_BG
    })

    local isz = math.floor(32 * _G.density_scale)
    local tfs = math.max(math.floor(12 * _G.density_scale), math.min(math.floor(18 * _G.density_scale), math.floor(screen_h / 32 * _G.density_scale)))
    local txh = tfs * 2 + 8

    for i = 1, ap do
        local idx = start_idx + i - 1
        if idx > #apps then break end
        local app = apps[idx]

        local col = (i - 1) % gcs
        local row = math.floor((i - 1) / gcs)

        local trw = gcs * cw + (gcs - 1) * gm
        local sx = math.floor((screen_w - trw) / 2 + 0.5)
        local x = sx + col * (cw + gm)
        local y = row * (ch + gm) + gtp

        local crd = airui.container({
            parent = gcn, x = x, y = y, w = cw, h = ch,
            radius = 12, border_width = 1,
            on_click = function()
                if app.is_builtin then
                    sys.publish("OPEN_" .. app.win .. "_WIN")
                else
                    log.info("iw", "open app", app.path)
                    exapp.open(app.path)
                end
            end
        })

        local isr = app.icon
        local ix = math.floor((cw - isz) / 2 + 0.5)
        airui.image({
            parent = crd, x = ix, y = 8, w = isz, h = isz, src = isr
        })

        airui.label({
            parent = crd, x = 4, y = isz + 10,
            w = cw - 8, h = txh,
            text = app.name or "未知", font_size = tfs,
            color = COLOR_TEXT, align = airui.TEXT_ALIGN_CENTER
        })
    end

    return gcn
end

local function rap()
    if not tv then return end

    local apps = eac
    local ta = #apps
    local tp = (ta == 0) and 0 or math.ceil(ta / ap)

    local ctc = tv:get_tab_count()
    local etc = 1 + tp

    for i = ctc - 1, etc, -1 do
        if pg[i] then
            pg[i]:destroy()
            pg[i] = nil
        end
        tv:remove_tab(i)
    end

    for pi = 1, tp do
        local ti = pi
        local si = (pi - 1) * ap + 1

        if ti < ctc then
            local ep = tv:get_content(ti)
            if ep then
                if pg[ti] then
                    pg[ti]:destroy()
                end
                local ng = bgp(ep, si, apps)
                pg[ti] = ng
            end
        else
            local np = tv:add_tab("")
            if np then
                local g = bgp(np, si, apps)
                pg[ti] = g
            end
        end
    end

    if ct >= etc then
        ct = etc - 1
        tv:set_active(ct)
    end
    upi()
end

local function lea()
    local ls = {}
    local ins, _ = exapp.list_installed()

    for app_dir, info in pairs(ins) do
        local ibd = false
        for _, b in ipairs(ba) do
            if info.cn_name == b.name then
                ibd = true
                break
            end
        end
        if not ibd then
            table.insert(ls, {
                name = info.cn_name or app_dir,
                icon = info.icon_path or "/luadb/img.png",
                is_builtin = false,
                path = info.path,
                install_time = info.install_time,
            })
        end
    end

    table.sort(ls, function(a, b)
        local ta = a.install_time
        local tb = b.install_time
        if ta == nil and tb == nil then
            return a.name < b.name
        elseif ta == nil then
            return false
        elseif tb == nil then
            return true
        else
            if ta == tb then
                return a.name < b.name
            end
            return ta < tb
        end
    end)

    eac = ls
    rap()
end

local function utd(time_str, date_str, weekday_str)
    if time_str then sc.time = time_str end
    if date_str then sc.date = date_str end
    if weekday_str then sc.weekday = weekday_str end
    if not dl then return end
    if btl then
        btl:set_text(sc.time)
    end
    dl:set_text(sc.date .. " " .. sc.weekday)
end

local function uwi(level)
    if level == nil then return end
    sc.wifi_level = level
    if not wi then return end
    local imn = "wifixinhao" .. level .. ".png"
    wi:set_src("/luadb/" .. imn)
end

local function umi(level)
    if level == nil then return end
    sc.mobile_level = level
    if not mi then return end
    local ii
    if level == -1 then
        ii = 6
    elseif level == 1 then
        ii = 5
    else
        ii = level - 1
    end
    local imn = "4Gxinhao" .. ii .. ".png"
    mi:set_src("/luadb/" .. imn)
end

local function ost(current_time, current_date, current_weekday)
    utd(current_time, current_date, current_weekday)
end

local function osw(level)
    uwi(level)
end

local function osm(level)
    umi(level)
end

local function oc()
    cl()

    mc = airui.container({
        x = 0, y = 0, w = screen_w, h = screen_h,
        color = COLOR_BG, parent = airui.screen
    })

    local sb = airui.container({
        parent = mc, x = 0, y = 0, w = screen_w, h = th,
        color = COLOR_PRIMARY
    })
    local sis = math.floor(32 * _G.density_scale)
    local siy = math.floor((th - sis) / 2)
    local sfs = math.min(math.floor(40 * _G.density_scale), math.floor(th * 0.65 * _G.density_scale))
    local plh = math.min(sfs, math.floor(24 * _G.density_scale))
    local ply = math.floor((th - plh) / 2)
    local isp, isx
    if ia8 then
        isp = math.floor(8 * _G.density_scale)
        isx = screen_w - (sis * 2 + isp) - math.floor(12 * _G.density_scale)
    else
        isx = screen_w - sis - math.floor(12 * _G.density_scale)
    end
    wi = airui.image({
        parent = sb, x = isx, y = siy,
        w = sis, h = sis, src = "/luadb/wifixinhao0.png"
    })
    if ia8 then
        mi = airui.image({
            parent = sb,
            x = isx + sis + isp, y = siy,
            w = sis, h = sis, src = "/luadb/4Gxinhao6.png"
        })
    end
    if ia8 then
        pl = airui.label({
            parent = sb,
            x = 0, y = ply,
            w = screen_w - (sis * 2 + math.floor(8 * _G.density_scale)) - math.floor(20 * _G.density_scale),
            h = plh, text = pn, font_size = plh, color = COLOR_WHITE,
            align = airui.TEXT_ALIGN_CENTER
        })
    else
        pl = airui.label({
            parent = sb,
            x = 0, y = ply,
            w = screen_w - sis - math.floor(20 * _G.density_scale),
            h = plh, text = pn, font_size = plh, color = COLOR_WHITE,
            align = airui.TEXT_ALIGN_CENTER
        })
    end

    tv = airui.tabview({
        parent = mc,
        x = 0, y = th, w = screen_w, h = screen_h - th - pih,
        tabs = { "" }, switch_mode = "swipe",
        page_style = {
            tabbar_size = 0,
            pad = { method = airui.TABVIEW_PAD_ALL, value = 0 },
            bg_opa = 0
        }
    })

    local hp = tv:get_content(0)
    bhp(hp)

    local bb = airui.container({
        parent = mc,
        x = 0, y = screen_h - pih, w = screen_w, h = pih,
        color = COLOR_BG
    })
    pgl = airui.label({
        parent = bb, x = 0, y = 0, w = screen_w, h = pih,
        text = "1/1", font_size = math.floor(18 * _G.density_scale),
        color = COLOR_TEXT_SECONDARY, align = airui.TEXT_ALIGN_CENTER
    })

    tv:set_on_change(function(self, index)
        ct = index
        upi()
    end)

    lea()
    utd(sc.time, sc.date, sc.weekday)
    uwi(sc.wifi_level)
    umi(sc.mobile_level)

    tt = sys.timerLoopStart(function()
        utd(sc.time, sc.date, sc.weekday)
    end, 1000)
    sys.subscribe("STATUS_TIME_UPDATED", ost)
    if ia8 then
        sys.subscribe("STATUS_SIGNAL_UPDATED", osm)
    end
    sys.subscribe("STATUS_WIFI_SIGNAL_UPDATED", osw)
    sys.subscribe("APP_STORE_INSTALLED_UPDATED", function()
        lea()
    end)

    sys.publish("REQUEST_STATUS_REFRESH")
end

local function od()
    if tt then
        sys.timerStop(tt)
        tt = nil
    end
    sys.unsubscribe("STATUS_TIME_UPDATED", ost)
    if ia8 then
        sys.unsubscribe("STATUS_SIGNAL_UPDATED", osm)
    end
    sys.unsubscribe("STATUS_WIFI_SIGNAL_UPDATED", osw)
    sys.unsubscribe("APP_STORE_INSTALLED_UPDATED", lea)

    if tv then tv:destroy() end
    if mc then mc:destroy() end
end

local function ogf()
    utd(sc.time, sc.date, sc.weekday)
    uwi(sc.wifi_level)
    umi(sc.mobile_level)
    lea()
end

local function olf() end

local function oh()
    wid = exwin.open({
        on_create = oc,
        on_destroy = od,
        on_lose_focus = olf,
        on_get_focus = ogf,
    })
end

sys.subscribe("OPEN_IDLE_WIN", oh)
