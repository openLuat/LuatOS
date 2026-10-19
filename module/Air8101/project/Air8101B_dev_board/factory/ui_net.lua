--[[
@module  ui_net
@summary 网络优先级应用：三张网卡排序（上移 / 下移，立即生效）+ 状态 + 当前出口
@version 4.0
@date    2026.10.19
@usage
    sys.publish("OPEN_NET_WIN")

入口：桌面「网络优先级」

和 Air8301 出厂固件（multi_net_win + net_config）同一套数据链路：
    上移 / 下移 → net_config.save()（写 fskv）→ 发布 NET_CONFIG_UPDATED
    → app_net 合并连续改动后重新 exnetif.set_priority_order（增量重排，不用重启）

页面结构（设计坐标 800×480，内容区 422 高）
    y  12  当前出口条（出口名 + IP + 已连接数量）
    y  72  三张网卡卡片（每张 88，间距 8）：序号 / 名称 / 生效标记 / 状态 / IP / 上移 / 下移
    y 364  恢复默认顺序 + 操作说明

刷新策略：列表只在“顺序变化 / 进出页面”时重建；
状态文字、IP 与生效标记走增量 set_text（状态变化由 APP_NET_CHANGED 驱动）。
]]

local exwin      = require "exwin"
local ui         = require "ui_kit"
local status     = require "app_status"
local app_net    = require "app_net"
local net_config = require "net_config"
local T          = require "ui_theme"

local C, F, G = T.COLOR, T.FONT, T.GAP
local DW      = T.SCREEN.DW

local CARD_X, CARD_W   = G.M, DW - G.M * 2
local CARD_H, CARD_GAP = 88, 8
local LIST_Y           = 72

local win_id, page, list_box, active_label, count_label
local rows = {}       -- rows[i] = { key, state, ip, tag }

--- key → adapter（LWIP_GP_GW 在个别固件叫 LWIP_GP，兜底一下）
local function adapter_of(key)
    if key == "eth"  then return socket.LWIP_ETH end
    if key == "wifi" then return socket.LWIP_STA end
    if key == "4g"   then return socket.LWIP_GP_GW or socket.LWIP_GP end
end

--- 这张网卡当前是不是默认出口
local function is_active(key)
    local adapter = adapter_of(key)
    if not adapter then return false end
    return socket.dft() == adapter and socket.adapter(adapter) and true or false
end

--- 网卡状态文字 / 颜色 / 副文本（IP 或排查提示）
local function state_of(key)
    if not app_net.supported(key) then
        return "本板未配置", C.TEXT_WEAK, "—"
    end

    local adapter = adapter_of(key)
    local s = adapter and app_net.get(adapter)
    if s and s.ready and s.ip then
        return "已连接", C.OK, s.ip
    end

    if key == "wifi" then
        local ssid = app_net.get_wifi_cred()
        if not ssid or ssid == "" then
            return "未配置热点", C.WARN, "点「WiFi」应用配网"
        end
        return "连接中", C.WARN, "热点 " .. ssid
    end
    if key == "4g" then
        return "未连接", C.TEXT_WEAK, "检查 SIM 卡 / VBAT_4G"
    end
    return "未连接", C.TEXT_WEAK, "检查网线"
end

-- ===== 列表 =====

--- 上移 / 下移：交换相邻两项 → 保存 → app_net 立即重排
local function move(i, delta)
    local p = app_net.priority()
    local j = i + delta
    if j < 1 or j > #p then return end

    p[i], p[j] = p[j], p[i]
    app_net.set_priority(p)
    if page then page.toast("优先级已保存，正在切换") end
end

--- 重建网卡列表（只在顺序变化 / 进页面时调用）
local function build_list()
    if not page then return end
    if list_box then
        pcall(function() list_box:destroy() end)
        list_box = nil
    end
    rows = {}

    local p = app_net.priority()
    list_box = ui.box({
        parent = page.body, x = 0, y = LIST_Y, w = DW,
        h = CARD_H * #p + CARD_GAP * (#p - 1),
    })

    for i, key in ipairs(p) do
        local y = (i - 1) * (CARD_H + CARD_GAP)
        local supported = app_net.supported(key)
        local card = ui.card({
            parent = list_box, x = CARD_X, y = y, w = CARD_W, h = CARD_H,
            border = supported and C.BORDER or C.BG,
            color = supported and C.CARD or C.BG,
        })

        -- 序号：表示优先级档位（1 最高）
        ui.label({
            parent = card, x = 16, y = 26, w = 36, h = 36,
            text = tostring(i), size = F.NORMAL,
            color = supported and C.PRIMARY or C.TEXT_WEAK,
            align = airui.TEXT_ALIGN_CENTER,
        })

        ui.label({
            parent = card, x = 62, y = 12, w = 160, h = 30,
            text = net_config.name(key), size = F.NORMAL,
            color = supported and C.TEXT or C.TEXT_WEAK,
        })

        local tag = ui.label({
            parent = card, x = 232, y = 16, w = 70, h = 24,
            text = "", size = F.TINY, color = C.PRIMARY,
        })

        local text, color, sub = state_of(key)
        local state_label = ui.label({
            parent = card, x = 62, y = 50, w = 150, h = 24,
            text = text, size = F.SMALL, color = color,
        })
        local ip_label = ui.label({
            parent = card, x = 214, y = 50, w = 330, h = 24,
            text = sub or "—", size = F.TINY, color = C.TEXT_SUB,
        })
        rows[i] = { key = key, state = state_label, ip = ip_label, tag = tag }

        local first, last = (i == 1), (i == #p)
        local up_disabled   = first or not supported
        local down_disabled = last or not supported

        ui.ghost_button({
            parent = card, x = CARD_W - 202, y = 24, w = 86, h = 40,
            text = "上移", size = F.SMALL,
            color = up_disabled and C.BG or C.PRIMARY_SOFT,
            text_color = up_disabled and C.DISABLED or C.PRIMARY,
            on_click = function()
                if not up_disabled then move(i, -1) end
            end,
        })
        ui.ghost_button({
            parent = card, x = CARD_W - 108, y = 24, w = 86, h = 40,
            text = "下移", size = F.SMALL,
            color = down_disabled and C.BG or C.PRIMARY_SOFT,
            text_color = down_disabled and C.DISABLED or C.PRIMARY,
            on_click = function()
                if not down_disabled then move(i, 1) end
            end,
        })
    end
end

--- 状态类文字增量刷新（每秒一次，不重建控件）
local function refresh_states()
    local online = 0
    for _, r in ipairs(rows) do
        local text, color, sub = state_of(r.key)
        if r.state then
            r.state:set_text(text)
            pcall(function() r.state:set_color(color) end)
        end
        if r.ip then r.ip:set_text(sub or "—") end
        if r.tag then r.tag:set_text(is_active(r.key) and "● 生效" or "") end
        if text == "已连接" then online = online + 1 end
    end
    if count_label then
        count_label:set_text("已连接 " .. online .. " / " .. #rows)
    end
end

--- 刷新当前出口条与标题栏副标题
local function refresh_active()
    if not (page and active_label) then return end
    local adapter, name = app_net.get_active()
    if adapter and socket.adapter(adapter) then
        local ip = socket.localIP(adapter)
        active_label:set_text("当前出口：" .. tostring(name) .. "（" .. tostring(ip or "已就绪") .. "）")
        page.set_subtitle(status.net_summary())
    else
        active_label:set_text("当前出口：无（检查网线 / WiFi 凭据 / SIM 卡）")
        page.set_subtitle("未联网")
    end
end

local function refresh_all()
    refresh_states()
    refresh_active()
end

local function create_ui()
    page = ui.page({
        title    = "网络优先级",
        subtitle = "查询中",
        on_back  = function() if win_id then exwin.close(win_id) end end,
    })

    active_label = ui.label({
        parent = page.body, x = G.M, y = 14, w = DW - G.M * 2 - 140, h = 30,
        text = "当前出口：查询中", size = F.NORMAL, color = C.TEXT,
    })
    count_label = ui.label({
        parent = page.body, x = DW - G.M - 140, y = 18, w = 140, h = 26,
        text = "", size = F.TINY, color = C.TEXT_WEAK,
        align = airui.TEXT_ALIGN_RIGHT,
    })

    ui.divider({ parent = page.body, x = G.M, y = 56, w = DW - G.M * 2 })

    build_list()

    ui.ghost_button({
        parent = page.body, x = G.M, y = 364, w = 180, h = 42,
        text = "恢复默认顺序", size = F.SMALL,
        on_click = function()
            local _, changed = app_net.reset_priority()
            if page then
                page.toast(changed and "已恢复默认顺序，正在切换" or "当前已是默认顺序")
            end
        end,
    })

    ui.label({
        parent = page.body, x = G.M + 196, y = 366, w = DW - G.M * 2 - 196, h = 40,
        text = "第一行优先级最高，调整后立即生效，无需重启；\n高优先级出口掉线时自动切到下一张可用网卡",
        size = F.TINY, color = C.TEXT_WEAK,
    })
end

-- ===== 生命周期 =====

local on_config_updated

local function on_create()
    create_ui()
    refresh_all()
    sys.subscribe("STATUS_UPDATED", refresh_all)
    sys.subscribe("APP_NET_CHANGED", refresh_all)
    sys.subscribe("NET_CONFIG_UPDATED", on_config_updated)
end

--- 优先级被改（本页或其它入口）→ 重建顺序并刷新
-- 延迟一帧再重建：本页按钮的回调栈里还持有旧控件，立刻 destroy 容易踩到野指针
local rebuild_timer
on_config_updated = function()
    if rebuild_timer then sys.timerStop(rebuild_timer) end
    rebuild_timer = sys.timerStart(function()
        rebuild_timer = nil
        build_list()
        refresh_all()
    end, 30)
end

local function on_destroy()
    if rebuild_timer then
        sys.timerStop(rebuild_timer)
        rebuild_timer = nil
    end
    sys.unsubscribe("STATUS_UPDATED", refresh_all)
    sys.unsubscribe("APP_NET_CHANGED", refresh_all)
    sys.unsubscribe("NET_CONFIG_UPDATED", on_config_updated)
    if page then
        page.destroy()
        page = nil
    end
    list_box, active_label, count_label, rows = nil, nil, nil, {}
    win_id = nil
end

sys.subscribe("OPEN_NET_WIN", function()
    win_id = exwin.open({
        on_create     = on_create,
        on_destroy    = on_destroy,
        on_get_focus  = refresh_all,
        on_lose_focus = function() end,
    })
end)
