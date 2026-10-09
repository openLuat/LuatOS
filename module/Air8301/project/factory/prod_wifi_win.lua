--[[
@module  prod_wifi_win
@summary WiFi页面（产测模式），显示当前连接状态 + 扫描结果
@version 1.0
@date    2026.10.08
@author  江访
@version_note 产测专属：消息名前缀 OPEN_PROD_WIFI_WIN，避免与业务页面冲突

@usage
本页面提供WiFi信息展示功能：
1、当前是否连接WiFi及连接状态（SSID + 信号强度）
2、刷新按钮触发扫描（通过 WIFI_SCAN_REQ/WIFI_SCAN_RESULT 与 prod_wifi_app 交互）
3、扫描结果列表展示

不提供WiFi开关功能。

视觉：ui_theme 深色玻璃态（状态行 + 工具行 + 结果面板）。
]]

local theme = require "ui_theme"

local win_id = nil
local main_container, content
local wifi_status_label = nil
local scan_list_label = nil
local scan_count_label = nil
local page_label = nil

-- 扫描结果分页（列表由本页自持，配合「上一页 / 下一页」浏览全部结果）
-- 说明：airui.container 无滚动能力（无 scrollbar / scroll 方法），
--       480×272 小屏下以分页替代滑动条，翻页按钮比滚动条更好按。
local scan_list = {}
local scan_page = 1
local PAGE_SIZE = 5      -- 每页条数：结果面板可容 5 行

-- 布局常量（内容区 464×210：40 + 6 + 30 + 6 + 128 = 210）
local STATUS_H = 40
local TOOL_H   = 30
local GAP      = 6

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
更新WiFi连接状态显示

@local
@function on_status_wifi_updated
]]
local function on_status_wifi_updated(connected, ssid, level, rssi)
    if not exwin.is_active(win_id) then return end
    if not wifi_status_label then return end
    local text, color
    if connected then
        text = "已连接 " .. tostring(ssid or "") .. theme.CHAR.sep
        if rssi and rssi ~= 0 then
            text = text .. " " .. tostring(rssi) .. "dBm"
        end
        color = theme.SEM.success
    else
        text, color = "未连接", theme.SEM.danger
    end
    wifi_status_label:set_text(text)
    wifi_status_label:set_color(color)
end

--[[
渲染当前页的扫描结果（含页码）

以 scan_list_label 是否为 nil 作为页面存活性判定（销毁后该引用被置 nil）。

@local
@function render_scan_list
]]
local function render_scan_list()
    if not scan_list_label then return end
    local total = #scan_list
    if total == 0 then
        scan_list_label:set_text("未发现WiFi")
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
        lines[#lines + 1] = tostring(ap.ssid or "未知") .. "  " .. tostring(ap.rssi or 0) .. "dBm"
    end
    scan_list_label:set_text(table.concat(lines, "\n"))
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
    if not scan_list_label then return end
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
    if not scan_list_label then return end
    local pages = math.ceil(#scan_list / PAGE_SIZE)
    if scan_page < pages then
        scan_page = scan_page + 1
        render_scan_list()
    end
end

--[[
WIFI_SCAN_RESULT 消息回调：缓存扫描结果并回到第 1 页

@local
@function on_scan_result
@param results table 扫描结果列表
]]
local function on_scan_result(results)
    if not scan_list_label then return end
    scan_list = {}
    if results and type(results) == "table" then
        for _, entry in ipairs(results) do
            if type(entry) == "table" then
                scan_list[#scan_list + 1] = { ssid = entry.ssid, rssi = entry.rssi }
            end
        end
    end
    scan_page = 1
    local total = #scan_list
    if scan_count_label then
        if total > 0 then
            scan_count_label:set_text("发现 " .. tostring(total) .. " 个WiFi")
        else
            scan_count_label:set_text("未发现WiFi")
        end
    end
    render_scan_list()
end

--[[
刷新按钮点击：请求扫描

@local
@function on_refresh_click
]]
local function on_refresh_click()
    if not exwin.is_active(win_id) then return end
    if scan_list_label then
        scan_list_label:set_text("扫描中...")
    end
    if scan_count_label then
        scan_count_label:set_text("")
    end
    sys.publish("WIFI_SCAN_REQ")
end

--[[
创建UI界面

@local
@function create_ui
]]
local function create_ui()
    local ctx = theme.page({ title = "WiFi", on_back = on_back_click })
    main_container = ctx.base
    content = ctx.base

    local y = ctx.y

    -- 连接状态
    local _, l_status = theme.kv_row(ctx.base, {
        x = ctx.x, y = y, w = ctx.w, h = STATUS_H, label = "连接状态", value = "未连接" })
    wifi_status_label = l_status
    y = y + STATUS_H + GAP

    -- 工具行：标题 + 计数 + 刷新按钮
    local btn_w = 96
    local ty = y + math.floor((TOOL_H - 19) / 2)
    theme.label(ctx.base, {
        x = ctx.x, y = ty, w = 90, h = 19,
        text = "可用WiFi", px_size = 16, color = theme.C.t3 })
    scan_count_label = theme.label(ctx.base, {
        x = ctx.x + 92, y = ty, w = ctx.w - 92 - btn_w - 8, h = 19,
        text = "", px_size = 16, color = theme.C.t2 })
    theme.btn(ctx.base, {
        x = ctx.x + ctx.w - btn_w, y = y, w = btn_w, h = TOOL_H,
        text = "刷新扫描", on_click = on_refresh_click })
    y = y + TOOL_H + GAP

    -- 扫描结果面板：分页列表 + 翻页条
    local list_h = ctx.h - (y - ctx.y)
    if list_h < 60 then list_h = 60 end
    local list_card = theme.card(ctx.base, {
        x = ctx.x, y = y, w = ctx.w, h = list_h,
        color = theme.C.panel, radius = theme.R.lg, border = theme.C.stroke_soft })
    scan_list_label = theme.label(list_card, {
        x = 12, y = 6, w = ctx.w - 24, h = PAGE_SIZE * 19,
        text = "点击\"刷新扫描\"开始", px_size = 16, color = theme.C.t1 })

    -- 翻页条（上一页 / 页码 / 下一页）
    local py = list_h - 24
    local py_min = 6 + PAGE_SIZE * 19 + 2
    if py < py_min then py = py_min end
    theme.ghost(list_card, {
        x = 12, y = py, w = 80, h = 20,
        text = "上一页", on_click = on_prev_page })
    page_label = theme.label(list_card, {
        x = 100, y = py, w = ctx.w - 200, h = 20,
        text = "0/0", px_size = 16, color = theme.C.t2,
        align = airui.TEXT_ALIGN_CENTER })
    theme.ghost(list_card, {
        x = ctx.w - 12 - 80, y = py, w = 80, h = 20,
        text = "下一页", on_click = on_next_page })
end

--[[
窗口创建回调

@local
@function on_create
]]
local function on_create()
    create_ui()
    sys.subscribe("WIFI_SCAN_RESULT", on_scan_result)
    sys.subscribe("STATUS_WIFI_UPDATED", on_status_wifi_updated)
    -- 主动查询一次当前WiFi状态
    sys.publish("NETWORK_STATUS_QUERY")
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
    scan_list_label = nil
    wifi_status_label = nil
    scan_count_label = nil
    page_label = nil
    sys.unsubscribe("WIFI_SCAN_RESULT", on_scan_result)
    sys.unsubscribe("STATUS_WIFI_UPDATED", on_status_wifi_updated)
    win_id = nil
end

--[[
窗口获得焦点回调

@local
@function on_get_focus
]]
local function on_get_focus()
    -- 重新获得焦点时刷新连接状态
    sys.publish("NETWORK_STATUS_QUERY")
end

--[[
窗口失去焦点回调

@local
@function on_lose_focus
]]
local function on_lose_focus() end

--[[
OPEN_PROD_WIFI_WIN 消息处理器

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

sys.subscribe("OPEN_PROD_WIFI_WIN", open_handler)
