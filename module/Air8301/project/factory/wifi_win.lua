--[[
@module  wifi_win
@summary WiFi 配网 / 状态 / 扫描页面（8301出厂固件）
@version 1.0
@date    2026.10.09
@author  江访

@version_note
  v2.1：修复「配网 / 扫描」两个页签按钮下方的滚动条 —— 页签文字标签原为满宽贴边，
        触发容器（LVGL 对象）在子元素贴边时绘制滚动条；改为左右各内缩 2px。
  v2.0：新增 WiFi 动态配置能力（业务模式）
    - 页面改为「配网 / 扫描」双页签布局：480×272 小屏单页放不下配网输入区与扫描结果区，
      拆成两个页签后各自拥有完整内容区，互不挤压。
    - 新增「配网」页签：WiFi 名称(SSID) 输入框 + WiFi 密码 输入框 + 连接按钮。
      点击连接即写 net_config（fskv 持久化）并广播 NET_CONFIG_UPDATED，
      由 net_drv 自动断开重连，无需重启、无需重进页面。
    - 新增实时状态提示行：未连接 / 已保存正在连接 / 已连接 xxx。
    - 「扫描」页签保留原有「状态三行 + 扫描按钮 + 结果分页」，
      翻页按钮改放结果面板标题行右侧，把纵向空间让给列表。
    - 软键盘沿用 rs485_win 的「显式销毁」范式（页面销毁前先销毁键盘），
      避免退出页面后键盘残留在屏幕上。

@usage
进入页面默认停在「配网」页签；输入 SSID/密码后点「连接」即保存并重连。
- 订阅 STATUS_WIFI_UPDATED 实时更新连接状态
- 打开页面时发布 NETWORK_STATUS_QUERY 主动查询一次
- 订阅 WLAN_SCAN_DONE 显示扫描结果
]]

local theme = require "ui_theme"
local net_config = require "net_config"

local win_id = nil
local main_container

-- 软键盘（页面级单例，退出页面必须显式销毁）
local kb = nil

-- 本页 UI 存活性标志：只由 on_create / on_destroy 维护
local ui_alive = false

-- 页签状态与控件
local cur_tab = "config"          -- config / scan
local tab_cfg_btn, tab_cfg_lbl
local tab_scan_btn, tab_scan_lbl
local panel_cfg, panel_scan

-- 扫描页签控件
local ssid_label, rssi_label, ip_label, scan_label, page_label

-- 配网页签控件
local cfg_ssid_input, cfg_pwd_input, cfg_tip_label

-- 扫描结果分页（列表由本页自持，配合「上一页 / 下一页」浏览全部结果）
-- 说明：airui.container 无滚动能力（既无 scrollbar 也无 scroll 方法），
--       故 480×272 小屏下以分页替代滑动条。
local scan_list = {}
local scan_page = 1
local PAGE_SIZE = 2      -- 每页条数：受页签条压缩后的结果面板高度限制

-- 布局常量（内容区 464×210）
local TAB_H   = 26       -- 页签条高度
local TAB_W   = 88       -- 单个页签宽度
local TAB_GAP = 6        -- 页签间距
local ROW_H   = 28       -- 状态行行高
local BTN_H   = 26       -- 扫描按钮高度
local GAP     = 4
local IN_H    = 36       -- 输入框高度

--[[
创建软键盘（页面级单例）

@local
@function ensure_keyboard
@return userdata 键盘对象
]]
local function ensure_keyboard()
    if kb then return kb end
    kb = airui.keyboard({
        x = 0,
        y = 0,                 -- 0 = 键盘下边缘贴屏幕底部（官方语义），向上展开 h 像素
        w = theme.SCREEN_W,
        h = 90,
        mode = "text",
        preview = false,       -- 关闭预览框：部分 airui 版本下预览框不随键盘销毁
        auto_hide = true,
    })
    return kb
end

--[[
关闭并销毁软键盘（页面销毁时必须调用）

airui 的键盘不属于页面容器，且输入框实际绑定的键盘未必等于外部创建的那个。
因此这里做「双保险」，且必须在本页容器销毁之前调用（之后 textarea 已失效）：
  1) 通过输入框的 get_keyboard() 取到它实际使用的键盘并销毁；
  2) 再销毁本模块自己创建的实例（若与上一步是同一对象则跳过）。

@local
@function destroy_keyboard
]]
local function destroy_keyboard()
    local function kill(k)
        if not k then return end
        pcall(function() k:hide() end)      -- 先隐藏，避免销毁瞬间残留一帧
        pcall(function() k:destroy() end)
    end

    -- 1) 输入框实际绑定的键盘
    if cfg_ssid_input then
        local ok, k = pcall(function() return cfg_ssid_input:get_keyboard() end)
        if ok and k and k ~= kb then kill(k) end
    end
    if cfg_pwd_input then
        local ok, k = pcall(function() return cfg_pwd_input:get_keyboard() end)
        if ok and k and k ~= kb then kill(k) end
    end

    -- 2) 本模块创建的键盘
    kill(kb)
    kb = nil
end

--[[
导航栏返回按钮点击

@local
@function on_back_click
]]
local function on_back_click()
    if not ui_alive then return end
    exwin.close(win_id)
end

--[[
刷新页签高亮（激活页签：琥珀实底 + 深色文字；未激活：透明底 + 次级文字）

@local
@function paint_tabs
]]
local function paint_tabs()
    local cfg_on = (cur_tab == "config")

    if tab_cfg_btn then
        pcall(function()
            tab_cfg_btn:set_color(theme.C.amber, cfg_on and 255 or 0)
            tab_cfg_btn:set_border_color(cfg_on and theme.C.amber or theme.C.stroke)
        end)
    end
    if tab_cfg_lbl then
        pcall(function() tab_cfg_lbl:set_color(cfg_on and theme.C.on_amber or theme.C.t2) end)
    end

    if tab_scan_btn then
        pcall(function()
            tab_scan_btn:set_color(theme.C.amber, cfg_on and 0 or 255)
            tab_scan_btn:set_border_color(cfg_on and theme.C.stroke or theme.C.amber)
        end)
    end
    if tab_scan_lbl then
        pcall(function() tab_scan_lbl:set_color(cfg_on and theme.C.t2 or theme.C.on_amber) end)
    end
end

--[[
切换页签（只切显隐，不重建控件，保证输入框内容不丢失）

@local
@function switch_tab
@param string name 目标页签（config / scan）
]]
local function switch_tab(name)
    if name ~= "config" and name ~= "scan" then return end
    if name == cur_tab then return end
    cur_tab = name

    local cfg_on = (name == "config")
    if panel_cfg then
        pcall(function() panel_cfg:set_hidden(not cfg_on) end)
    end
    if panel_scan then
        pcall(function() panel_scan:set_hidden(cfg_on) end)
    end
    paint_tabs()
end

--[[
WiFi 状态更新回调（同时刷新扫描页签的状态行与配网页签的提示行）

@local
@function on_status_wifi_updated
@param connected boolean 是否已连接
@param ssid string WiFi名称
@param level number 信号等级
@param rssi number 信号强度dBm
]]
local function on_status_wifi_updated(connected, ssid, level, rssi)
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
    if cfg_tip_label then
        if connected then
            cfg_tip_label:set_text("已连接：" .. tostring(ssid or "--"))
        else
            cfg_tip_label:set_text("未连接")
        end
    end
end

--[[
渲染当前页的扫描结果（含页码）

以 scan_label 是否为 nil 作为页面存活性判定（页面销毁后该引用被置 nil）。

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
    if not ui_alive then return end
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
连接按钮点击：保存 WiFi 配置并触发自动重连

写入 net_config 后会广播 NET_CONFIG_UPDATED，
net_drv.on_net_config_updated 收到后执行 wlan.disconnect() + wlan.connect(ssid, pwd)。

@local
@function on_connect_click
]]
local function on_connect_click()
    if not ui_alive then return end
    if not cfg_ssid_input then return end
    local ssid = cfg_ssid_input:get_text() or ""
    local pwd  = cfg_pwd_input and cfg_pwd_input:get_text() or ""
    -- 去除首尾空白（软键盘容易带出空格）
    ssid = tostring(ssid):gsub("^%s+", ""):gsub("%s+$", "")
    pwd  = tostring(pwd or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if #ssid == 0 then
        if cfg_tip_label then cfg_tip_label:set_text("请输入 WiFi 名称") end
        return
    end
    net_config.save({ wifi_ssid = ssid, wifi_pwd = pwd })
    if cfg_tip_label then
        cfg_tip_label:set_text("已保存，正在连接 " .. ssid)
    end
    log.info("wifi_win", "WiFi 配置已保存并触发重连", ssid)
end

--[[
创建「配网」页签内容

纵向：标题 19 + 输入 36 + 标题 19 + 输入 36 + 按钮 34 + 提示 19 = 163（内容区 180）

@local
@function create_config_panel
@param parent userdata 页签面板容器
@param w number 面板宽度
@param h number 面板高度
]]
local function create_config_panel(parent, w, h)
    theme.label(parent, {
        x = 0, y = 0, w = w, h = 19,
        text = "WiFi 名称（SSID）", px_size = 16, color = theme.C.t3 })

    cfg_ssid_input = theme.input(parent, {
        x = 0, y = 20, w = w, h = IN_H,
        placeholder = "请输入 WiFi 名称", px_size = 16,
        keyboard = ensure_keyboard(),
    })

    theme.label(parent, {
        x = 0, y = 60, w = w, h = 19,
        text = "WiFi 密码", px_size = 16, color = theme.C.t3 })

    cfg_pwd_input = theme.input(parent, {
        x = 0, y = 80, w = w, h = IN_H,
        placeholder = "请输入 WiFi 密码", px_size = 16,
        password_mode = true,
        keyboard = ensure_keyboard(),
    })

    theme.btn(parent, {
        x = 0, y = 122, w = w, h = 34,
        text = "连接", on_click = on_connect_click,
    })

    cfg_tip_label = theme.label(parent, {
        x = 0, y = 160, w = w, h = 19,
        text = "未连接", px_size = 16, color = theme.C.t3 })

    -- 回填当前已保存的配置，便于查看与修改
    local cfg = net_config.load()
    if cfg_ssid_input and cfg and cfg.wifi_ssid then
        cfg_ssid_input:set_text(tostring(cfg.wifi_ssid))
    end
    if cfg_pwd_input and cfg and cfg.wifi_pwd then
        cfg_pwd_input:set_text(tostring(cfg.wifi_pwd))
    end
end

--[[
创建「扫描」页签内容

纵向：SSID 行 28 + 信号/IP 行 28 + 扫描按钮 26 + 结果面板 86 = 168（内容区 180）

@local
@function create_scan_panel
@param parent userdata 页签面板容器
@param w number 面板宽度
@param h number 面板高度
]]
local function create_scan_panel(parent, w, h)
    local col_w = math.floor((w - 6) / 2)

    -- 当前 SSID（整行）
    local _, l_ssid = theme.kv_row(parent, {
        x = 0, y = 0, w = w, h = ROW_H, label = "当前 SSID", value = "--" })
    ssid_label = l_ssid

    -- 信号强度 + IP 地址（左右两列）
    local _, l_rssi = theme.kv_row(parent, {
        x = 0, y = ROW_H + GAP, w = col_w, h = ROW_H, label = "信号", value = "--" })
    rssi_label = l_rssi
    local _, l_ip = theme.kv_row(parent, {
        x = col_w + 6, y = ROW_H + GAP, w = col_w, h = ROW_H, label = "IP", value = "--" })
    ip_label = l_ip

    -- 扫描按钮（整行）
    local btn_y = (ROW_H + GAP) * 2
    theme.ghost(parent, {
        x = 0, y = btn_y, w = w, h = BTN_H,
        text = "扫描周边 WiFi", on_click = on_scan_click })

    -- 扫描结果面板：标题行（含页码与翻页）+ 分页列表
    local card_y = btn_y + BTN_H + GAP
    local result_h = h - card_y
    if result_h < 60 then result_h = 60 end
    local card = theme.card(parent, { x = 0, y = card_y, w = w, h = result_h })

    theme.label(card, {
        x = 10, y = 4, w = 110, h = 19,
        text = "扫描结果", px_size = 16, color = theme.C.t3 })
    page_label = theme.label(card, {
        x = 120, y = 4, w = 60, h = 19,
        text = "0/0", px_size = 16, color = theme.C.t2,
        align = airui.TEXT_ALIGN_LEFT })
    -- 翻页按钮放在标题行右侧，把纵向空间全部让给列表
    theme.ghost(card, {
        x = w - 10 - 56 - 6 - 56, y = 2, w = 56, h = 22,
        text = "上一页", on_click = on_prev_page })
    theme.ghost(card, {
        x = w - 10 - 56, y = 2, w = 56, h = 22,
        text = "下一页", on_click = on_next_page })

    scan_label = theme.label(card, {
        x = 10, y = 30, w = w - 20, h = PAGE_SIZE * 19,
        text = "点击上方按钮开始扫描", px_size = 16, color = theme.C.t1 })
end

--[[
创建 WiFi 页面 UI（双页签：配网 / 扫描）

@local
@function create_ui
]]
local function create_ui()
    local ctx = theme.page({ title = "WiFi", on_back = on_back_click })
    main_container = ctx.base

    -- 页签条
    local tab_y = ctx.y
    tab_cfg_btn, tab_cfg_lbl = (function()
        local btn = theme.card(ctx.base, {
            x = ctx.x, y = tab_y, w = TAB_W, h = TAB_H,
            color = theme.C.amber, opa = 255, radius = theme.R.md,
            border = theme.C.amber, on_click = function() switch_tab("config") end,
        })
        local lbl = theme.label(btn, {
            -- 宽度左右各内缩 2px：airui 容器底层是 LVGL 对象，子元素与容器边缘贴合
            -- （哪怕 0px 差）就会在容器下边缘画出滚动条，页签按钮下方那条横线即由此而来。
            x = 2, y = math.floor((TAB_H - 19) / 2), w = TAB_W - 4, h = 19,
            text = "配网", px_size = 16, color = theme.C.on_amber,
            align = airui.TEXT_ALIGN_CENTER,
            on_click = function() switch_tab("config") end,
        })
        return btn, lbl
    end)()

    tab_scan_btn, tab_scan_lbl = (function()
        local bx = ctx.x + TAB_W + TAB_GAP
        local btn = theme.card(ctx.base, {
            x = bx, y = tab_y, w = TAB_W, h = TAB_H,
            color = theme.C.surface, opa = 0, radius = theme.R.md,
            border = theme.C.stroke, on_click = function() switch_tab("scan") end,
        })
        local lbl = theme.label(btn, {
            -- 同「配网」页签：标签左右内缩 2px，消除子元素触边导致的容器滚动条
            x = 2, y = math.floor((TAB_H - 19) / 2), w = TAB_W - 4, h = 19,
            text = "扫描", px_size = 16, color = theme.C.t2,
            align = airui.TEXT_ALIGN_CENTER,
            on_click = function() switch_tab("scan") end,
        })
        return btn, lbl
    end)()

    -- 两个页签面板（透明底，只作布局容器）
    local py = ctx.y + TAB_H + GAP
    local ph = ctx.h - TAB_H - GAP
    if ph < 60 then ph = 60 end

    panel_cfg = theme.box(ctx.base, {
        x = ctx.x, y = py, w = ctx.w, h = ph, color = theme.C.bg, opa = 0 })
    panel_scan = theme.box(ctx.base, {
        x = ctx.x, y = py, w = ctx.w, h = ph, color = theme.C.bg, opa = 0 })

    create_config_panel(panel_cfg, ctx.w, ph)
    create_scan_panel(panel_scan, ctx.w, ph)

    -- 默认显示「配网」，隐藏「扫描」
    cur_tab = "config"
    pcall(function() panel_scan:set_hidden(true) end)
    paint_tabs()

    -- 主动查询一次网络状态
    sys.publish("NETWORK_STATUS_QUERY")
end

--[[
窗口创建回调

@local
@function on_create
]]
local function on_create()
    log.info("wifi_win", "[UI-MARK] WiFi 页 v2.1 已加载（配网 / 扫描 双页签）")
    ui_alive = true
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
    ui_alive = false
    -- 先销毁键盘（需在 textarea 失效之前取到其绑定的键盘）
    destroy_keyboard()
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    tab_cfg_btn, tab_cfg_lbl = nil, nil
    tab_scan_btn, tab_scan_lbl = nil, nil
    panel_cfg, panel_scan = nil, nil
    ssid_label, rssi_label, ip_label = nil, nil, nil
    scan_label, page_label = nil, nil
    cfg_ssid_input, cfg_pwd_input, cfg_tip_label = nil, nil, nil
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

单实例保护：避免同页多实例并存时互相覆盖 win_id。

@local
@function open_handler
]]
local function open_handler()
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
