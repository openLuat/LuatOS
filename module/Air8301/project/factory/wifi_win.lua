--[[
@module  wifi_win
@summary WiFi 状态与扫描页面（8301出厂固件）
@version 1.0
@date    2026.10.08
@author  江访

@usage
显示当前 WiFi 连接状态（SSID / 信号强度 / IP），支持扫描周边 WiFi。
- 订阅 STATUS_WIFI_UPDATED 实时更新
- 打开页面时发布 NETWORK_STATUS_QUERY 主动查询一次
- 订阅 WLAN_SCAN_DONE 显示扫描结果

视觉：ui_theme 深色玻璃态（键值卡片 + 幽灵按钮 + 结果面板）。
]]

local theme = require "ui_theme"

local win_id = nil
local main_container, content
local ssid_label, rssi_label, ip_label, scan_label
local page_label

-- 扫描结果分页（列表由本页自持，配合「上一页 / 下一页」浏览全部结果）
-- 说明：airui.container 无滚动能力（既无 scrollbar 也无 scroll 方法，
--       官方方法仅 set_color / set_border_color / set_on_click / hide / open /
--       move / get_pos / set_pos / is_destroyed / destroy），
--       故 480×272 小屏下以分页替代滑动条，且翻页按钮触摸区域比滚动条更好按。
local scan_list = {}
local scan_page = 1
local PAGE_SIZE = 3      -- 每页条数：结果面板仅容 3 行

-- 布局常量（内容区 464×210）
local COL_W   = 228
local COL_GAP = 8
local ROW_H   = 30       -- 顶部三行行高（较原 38 压缩，把空间让给结果面板）
local BTN_H   = 28
local GAP     = 4

--[[
导航栏返回按钮点击

@local
@function on_back_click
]]
local function on_back_click()
    if not exwin.is_active(win_id) then return end
    exwin.close(win_id)
end

--[[
WiFi 状态更新回调

@local
@function on_status_wifi_updated
@param connected boolean 是否已连接
@param ssid string WiFi名称
@param level number 信号等级
@param rssi number 信号强度dBm
]]
local function on_status_wifi_updated(connected, ssid, level, rssi)
    if not exwin.is_active(win_id) then return end
    if ssid_label then
        if connected then
            ssid_label:set_text(tostring(ssid or "--"))
            ssid_label:set_color(theme.SEM.success)
        else
            ssid_label:set_text("未连接")
            ssid_label:set_color(theme.SEM.danger)
        end
    end
    if rssi_label then
        rssi_label:set_text(connected and (tostring(rssi or 0) .. " dBm") or "--")
    end
    if ip_label then
        local ip = connected and socket.localIP(socket.LWIP_STA) or "--"
        ip_label:set_text(tostring(ip or "--"))
    end
end

--[[
渲染当前页的扫描结果（含页码）

以 scan_label 是否为 nil 作为页面存活性判定（页面销毁后该引用被置 nil），
不依赖会被旧实例清空的 win_id。

@local
@function render_scan_list
]]
local function render_scan_list()
    if not scan_label then return end
    local total = #scan_list
    if total == 0 then
        scan_label:set_text("未扫描到 WiFi")
        if page_label then page_label:set_text("0/0") end
        return
    end
    local pages = math.ceil(total / PAGE_SIZE)
    if scan_page < 1 then scan_page = 1 end
    if scan_page > pages then scan_page = pages end
    local first = (scan_page - 1) * PAGE_SIZE + 1
    local last  = first + PAGE_SIZE - 1
    if last > total then last = total end
    local lines = {}
    for i = first, last do
        local ap = scan_list[i]
        lines[#lines + 1] = tostring(ap.ssid or "--") .. "  " .. tostring(ap.rssi or 0) .. "dBm"
    end
    scan_label:set_text(table.concat(lines, "\n"))
    if page_label then
        page_label:set_text(tostring(scan_page) .. "/" .. tostring(pages))
    end
end

--[[
上一页

@local
@function on_prev_page
]]
local function on_prev_page()
    if not scan_label then return end
    if scan_page > 1 then
        scan_page = scan_page - 1
        render_scan_list()
    end
end

--[[
下一页

@local
@function on_next_page
]]
local function on_next_page()
    if not scan_label then return end
    local pages = math.ceil(#scan_list / PAGE_SIZE)
    if scan_page < pages then
        scan_page = scan_page + 1
        render_scan_list()
    end
end

--[[
WiFi 扫描按钮点击：触发扫描

@local
@function on_scan_click
]]
local function on_scan_click()
    if not exwin.is_active(win_id) then return end
    if scan_label then
        scan_label:set_text("扫描中...")
    end
    wlan.scan()
end

--[[
WiFi 扫描完成回调：缓存全部结果并回到第 1 页

@local
@function on_scan_done
]]
local function on_scan_done()
    if not scan_label then return end
    local list = wlan.scanResult() or {}
    scan_list = {}
    for _, ap in ipairs(list) do
        scan_list[#scan_list + 1] = { ssid = ap.ssid, rssi = ap.rssi }
    end
    scan_page = 1
    render_scan_list()
end

--[[
创建 WiFi 页面 UI

@local
@function create_ui
]]
local function create_ui()
    local ctx = theme.page({ title = "WiFi", on_back = on_back_click })
    main_container = ctx.base

    local y = ctx.y

    -- 当前 SSID（整行）
    local _, l_ssid = theme.kv_row(ctx.base, {
        x = ctx.x, y = y, w = ctx.w, h = ROW_H, label = "当前 SSID", value = "--" })
    ssid_label = l_ssid
    y = y + ROW_H + GAP

    -- 信号强度 + IP 地址（左右两列）
    local _, l_rssi = theme.kv_row(ctx.base, {
        x = ctx.x, y = y, w = COL_W, h = ROW_H, label = "信号", value = "--" })
    rssi_label = l_rssi
    local _, l_ip = theme.kv_row(ctx.base, {
        x = ctx.x + COL_W + COL_GAP, y = y, w = COL_W, h = ROW_H, label = "IP", value = "--" })
    ip_label = l_ip
    y = y + ROW_H + GAP

    -- 扫描按钮（整行）
    theme.ghost(ctx.base, {
        x = ctx.x, y = y, w = ctx.w, h = BTN_H, text = "扫描周边 WiFi", on_click = on_scan_click })
    y = y + BTN_H + GAP

    -- 扫描结果面板：标题行（含页码）+ 分页列表 + 翻页条
    local result_h = ctx.h - (y - ctx.y)
    local card = theme.card(ctx.base, { x = ctx.x, y = y, w = ctx.w, h = result_h })
    theme.label(card, {
        x = 10, y = 6, w = 200, h = 19,
        text = "扫描结果", px_size = 16, color = theme.C.t3 })
    page_label = theme.label(card, {
        x = ctx.w - 90, y = 6, w = 80, h = 19,
        text = "0/0", px_size = 16, color = theme.C.t2,
        align = airui.TEXT_ALIGN_RIGHT })
    scan_label = theme.label(card, {
        x = 10, y = 27, w = ctx.w - 20, h = PAGE_SIZE * 19,
        text = "点击上方按钮开始扫描", px_size = 16, color = theme.C.t1 })

    -- 翻页条（结果面板底部）
    local py = result_h - 24
    local py_min = 27 + PAGE_SIZE * 19 + 2
    if py < py_min then py = py_min end
    theme.ghost(card, {
        x = 10, y = py, w = 80, h = 20,
        text = "上一页", on_click = on_prev_page })
    theme.ghost(card, {
        x = ctx.w - 10 - 80, y = py, w = 80, h = 20,
        text = "下一页", on_click = on_next_page })

    -- 主动查询一次网络状态
    sys.publish("NETWORK_STATUS_QUERY")
end

--[[
窗口创建回调

@local
@function on_create
]]
local function on_create()
    create_ui()
    sys.subscribe("STATUS_WIFI_UPDATED", on_status_wifi_updated)
    sys.subscribe("WLAN_SCAN_DONE", on_scan_done)
end

--[[
窗口销毁回调

@local
@function on_destroy
]]
local function on_destroy()
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    content = nil
    ssid_label = nil
    rssi_label = nil
    ip_label = nil
    scan_label = nil
    page_label = nil
    sys.unsubscribe("STATUS_WIFI_UPDATED", on_status_wifi_updated)
    sys.unsubscribe("WLAN_SCAN_DONE", on_scan_done)
    win_id = nil
end

--[[
窗口获得焦点回调

@local
@function on_get_focus
]]
local function on_get_focus()
    sys.publish("NETWORK_STATUS_QUERY")
end

--[[
窗口失去焦点回调

@local
@function on_lose_focus
]]
local function on_lose_focus() end

--[[
OPEN_WIFI_WIN 消息处理器

@local
@function open_handler
]]
local function open_handler()
    -- 单实例保护：避免同页多实例并存时互相覆盖 win_id（会使点击准入判定失效）
    if win_id and exwin.is_active(win_id) then return end
    if win_id then
        exwin.close(win_id)
        win_id = nil
    end
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_lose_focus = on_lose_focus,
        on_get_focus = on_get_focus,
    })
end

sys.subscribe("OPEN_WIFI_WIN", open_handler)
