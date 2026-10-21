--[[
@module  wifi_win
@summary WiFi 配网 / 状态页面（扫描热点列表 → 点击热点输入密码，8301出厂固件）
@version 1.0
@date    2026.10.10
@author  江访

@version_note
  v3.0：配网交互重做（参考官方 electric_device 工程的手机风格交互）
    - 由原「配网 / 扫描」双页签改为单页：状态行 + 操作行 + 可点击热点列表（3 行/页）。
    - 扫描结果改为**可点击行**：点击任意热点即弹出密码输入弹窗（软键盘），
      不必再手工敲 SSID —— 解决原「扫描结果只是死文本、配网太麻烦」的痛点。
    - 弹窗含「连接 / 取消」，若该热点等于当前已保存的 SSID 则额外显示「忘记」。
    - 已保存热点在弹窗内预填密码；列表中状态列区分「已连接 / 已保存 / 未连接」。
    - 保留「手动输入」入口：用于隐藏 SSID 或扫描不到的热点，手动填写名称+密码。
    - 软键盘沿用页面级单例 + 退出页面显式销毁的范式（避免退出后键盘残留）。

@usage
进入页面即显示当前 WiFi 状态与热点列表。
- 点「扫描周边 WiFi」触发扫描，扫描完成后点击列表中任意热点 → 输入密码 → 点「连接」保存并重连。
- 点「手动输入」→ 手动填写 SSID 与密码后连接。
- 订阅 STATUS_WIFI_UPDATED 实时更新连接状态；订阅 WLAN_SCAN_DONE 显示扫描结果。
- 打开页面时发布 NETWORK_STATUS_QUERY 主动查询一次。

@note
配置写入 net_config（fskv 持久化）并广播 NET_CONFIG_UPDATED，由 net_drv 增量重排多网融合优先级
（exnetif 检测到 WiFi 凭证变化会自动断开重连），无需重启、无需重进页面。
「忘记网络」将清空 wifi_ssid / wifi_pwd 并断开 STA（net_drv 不再把 WiFi 纳入多网融合）。
]]

local theme = require "ui_theme"
local net_config = require "net_config"

local win_id = nil
local main_container

-- 软键盘（页面级单例，退出页面必须显式销毁）
local kb = nil

-- 本页 UI 存活性标志：只由 on_create / on_destroy 维护
local ui_alive = false

-- 扫描结果与分页（airui.container 无滚动能力，3 行/页翻页浏览）
local scan_list = {}
local scan_page = 1
local PAGE_SIZE = 3

-- 连接状态缓存
local wifi_connected = false
local cur_ssid = ""
local cur_rssi = 0

-- 页面控件引用
local status_label
local page_label
local list_rows = {}          -- 复用行：{ row, ssid, rssi, state }

-- 密码弹窗控件引用
local pwd_mask, pwd_panel, pwd_title
local pwd_ssid_input, pwd_pwd_input
local pwd_ssid = ""

-- 布局常量（内容区 464×210）
local STATUS_H = 26           -- 状态行高度
local OP_H     = 26           -- 操作行（扫描 / 手动输入 / 翻页）高度
local ROW_H    = 42           -- 热点行高度
local ROW_GAP  = 4            -- 热点行间距

-- 前向声明（解决 local 函数相互引用的解析顺序）
local render_list
local close_pwd_panel
local destroy_keyboard
local on_pwd_connect
local on_pwd_forget
local on_manual_click

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
关闭并销毁软键盘（页面销毁 / 关闭弹窗时必须调用）

airui 的键盘不属于页面容器，且输入框实际绑定的键盘未必等于外部创建的那个。
因此做「双保险」，且必须在输入框销毁之前调用（之后 textarea 已失效）：
  1) 通过输入框的 get_keyboard() 取到它实际使用的键盘并销毁；
  2) 再销毁本模块自己创建的实例（若与上一步是同一对象则跳过）。

@local
@function destroy_keyboard
]]
destroy_keyboard = function()
    local function kill(k)
        if not k then return end
        pcall(function() k:hide() end)      -- 先隐藏，避免销毁瞬间残留一帧
        pcall(function() k:destroy() end)
    end

    if pwd_ssid_input then
        local ok, k = pcall(function() return pwd_ssid_input:get_keyboard() end)
        if ok and k and k ~= kb then kill(k) end
    end
    if pwd_pwd_input then
        local ok, k = pcall(function() return pwd_pwd_input:get_keyboard() end)
        if ok and k and k ~= kb then kill(k) end
    end

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
刷新状态行（当前 SSID | 信号 | IP）

@local
@function refresh_status
]]
local function refresh_status()
    if not status_label then return end
    if wifi_connected then
        local ip = socket.localIP(socket.LWIP_STA) or "--"
        status_label:set_text("当前: " .. tostring(cur_ssid ~= "" and cur_ssid or "--")
            .. " | 信号 " .. tostring(cur_rssi or 0) .. "dBm | IP " .. tostring(ip))
        status_label:set_color(theme.SEM.success)
    else
        status_label:set_text("当前: 未连接")
        status_label:set_color(theme.C.t3)
    end
end

--[[
渲染当前页的热点列表（含页码）

行控件固定 3 个、复用于分页：按「(页-1)*3+行号」取当前热点刷新内容，
空位隐藏该行。行点击回调运行时按下标取热点，避免复用时绑定错行。

@local
@function render_list
]]
render_list = function()
    if not ui_alive then return end
    local total = #scan_list
    local pages = 0
    if total > 0 then pages = math.ceil(total / PAGE_SIZE) end
    if scan_page > pages then scan_page = pages end
    if scan_page < 1 then scan_page = 1 end
    if page_label then
        page_label:set_text(tostring(scan_page) .. "/" .. tostring(pages))
    end

    local cfg = net_config.load()
    local first = (scan_page - 1) * PAGE_SIZE
    for i = 1, PAGE_SIZE do
        local it = list_rows[i]
        if it then
            local ap = scan_list[first + i]
            if ap then
                it.row:set_hidden(false)
                it.ssid:set_text(tostring(ap.ssid or "--"))
                it.rssi:set_text((ap.rssi and (tostring(ap.rssi) .. "dBm")) or "--")
                local st, col
                if wifi_connected and ap.ssid == cur_ssid then
                    st, col = "已连接", theme.SEM.success
                elseif cfg.wifi_ssid and cfg.wifi_ssid ~= "" and ap.ssid == cfg.wifi_ssid then
                    st, col = "已保存", theme.C.primary
                else
                    st, col = "未连接", theme.C.t3
                end
                it.state:set_text(st)
                it.state:set_color(col)
            else
                it.row:set_hidden(true)
            end
        end
    end

    -- 列表为空时在状态行给出提示（仅此情形覆盖，避免影响连接状态显示）
    if total == 0 and status_label then
        status_label:set_text("未扫描到 WiFi，点「扫描周边 WiFi」重试")
        status_label:set_color(theme.C.t3)
    end
end

--[[
连接按钮点击：保存 WiFi 配置并触发自动重连

写入 net_config 后广播 NET_CONFIG_UPDATED，net_drv 增量重排多网融合优先级，
exnetif 检测到 WiFi 凭证变化后自动断开重连。

@local
@function on_pwd_connect
]]
on_pwd_connect = function()
    if not pwd_ssid_input then return end
    local ssid = tostring(pwd_ssid_input:get_text() or "")
    local pwd  = tostring((pwd_pwd_input and pwd_pwd_input:get_text()) or "")
    -- 去除首尾空白（软键盘容易带出空格）
    ssid = ssid:gsub("^%s+", ""):gsub("%s+$", "")
    pwd  = pwd:gsub("^%s+", ""):gsub("%s+$", "")
    if #ssid == 0 then
        if pwd_title then
            pwd_title:set_text("请输入 WiFi 名称")
            pwd_title:set_color(theme.SEM.danger)
        end
        return
    end
    net_config.save({ wifi_ssid = ssid, wifi_pwd = pwd })
    log.info("wifi_win", "WiFi 配置已保存并触发重连", ssid)
    close_pwd_panel()
end

--[[
忘记网络按钮点击：清空 WiFi 配置并断开 STA

清空后 net_drv 不再把 WiFi 纳入多网融合优先级（exnetif 配置表不含 WIFI 条目），
同时显式断开当前 STA 连接。

@local
@function on_pwd_forget
]]
on_pwd_forget = function()
    net_config.save({ wifi_ssid = "", wifi_pwd = "" })
    wlan.disconnect()
    log.info("wifi_win", "已忘记 WiFi 配置")
    close_pwd_panel()
end

--[[
立即销毁密码弹窗控件（不销毁键盘引用）

调用时机：页面销毁（on_destroy）等非触摸回调上下文。

@local
@function destroy_pwd_panel
]]
local function destroy_pwd_panel()
    if pwd_ssid_input then pwd_ssid_input:destroy(); pwd_ssid_input = nil end
    if pwd_pwd_input then pwd_pwd_input:destroy(); pwd_pwd_input = nil end
    if pwd_panel then pwd_panel:destroy(); pwd_panel = nil end
    if pwd_mask then pwd_mask:destroy(); pwd_mask = nil end
    pwd_title = nil
    pwd_ssid = ""
end

--[[
关闭密码弹窗

⚠️ 本函数常由弹窗内按钮（连接 / 取消 / 忘记）的触摸回调触发。
airui 容器的 destroy 会立即释放 LVGL 对象，若在触摸回调中销毁「触发按钮自身的父容器」，
存在释放态访问风险（同 weather_set_win 的处理）。因此这里**先隐藏弹窗**（视觉立即消失、防误触），
再延迟一帧执行真正的销毁；on_destroy 场景改为直接调 destroy_pwd_panel + destroy_keyboard。

@local
@function close_pwd_panel
]]
close_pwd_panel = function()
    if pwd_mask and pwd_mask.set_hidden then
        pcall(function() pwd_mask:set_hidden(true) end)
    end
    sys.timerStart(function()
        destroy_keyboard()
        destroy_pwd_panel()
    end, 20)
end

--[[
显示密码输入弹窗

@local
@function open_pwd_panel
@param string ssid 热点名称（手动输入时传 ""）
@param boolean manual 是否为「手动输入」入口
]]
local function open_pwd_panel(ssid, manual)
    if pwd_panel then return end
    pwd_ssid = tostring(ssid or "")

    local cfg = net_config.load()
    local is_saved = (pwd_ssid ~= "" and cfg.wifi_ssid and pwd_ssid == cfg.wifi_ssid)
    local pwd_prefill = is_saved and tostring(cfg.wifi_pwd or "") or ""

    -- 遮罩（覆盖全屏，防误触底层控件）
    pwd_mask = theme.box(airui.screen, {
        x = 0, y = 0, w = theme.SCREEN_W, h = theme.SCREEN_H,
        color = theme.C.scrim, opa = theme.OPA.scrim,
    })
    -- 弹窗面板（置于虚拟键盘上方，400×160）
    pwd_panel = theme.card(pwd_mask, { x = 40, y = 10, w = 400, h = 160 })

    pwd_title = theme.label(pwd_panel, {
        x = 20, y = 8, w = 360, h = 22,
        text = manual and "手动添加网络" or ("连接热点: " .. pwd_ssid),
        px_size = 18, color = theme.C.t1,
        align = airui.TEXT_ALIGN_CENTER,
    })

    local kbd = ensure_keyboard()
    pwd_ssid_input = theme.input(pwd_panel, {
        x = 20, y = 36, w = 360, h = 34,
        placeholder = "WiFi 名称（SSID）", px_size = 16, max_len = 32,
        text = pwd_ssid, keyboard = kbd,
    })
    pwd_pwd_input = theme.input(pwd_panel, {
        x = 20, y = 74, w = 360, h = 34,
        placeholder = "WiFi 密码", px_size = 16, max_len = 64,
        password_mode = true, text = pwd_prefill, keyboard = kbd,
    })

    theme.btn(pwd_panel, {
        x = 20, y = 116, w = 110, h = 34,
        text = "连接", on_click = on_pwd_connect,
    })
    theme.ghost(pwd_panel, {
        x = 145, y = 116, w = 110, h = 34,
        text = "取消", on_click = close_pwd_panel,
    })
    if is_saved then
        theme.ghost(pwd_panel, {
            x = 270, y = 116, w = 110, h = 34,
            text = "忘记", on_click = on_pwd_forget,
        })
    end
end

--[[
「手动输入」入口点击

@local
@function on_manual_click
]]
on_manual_click = function()
    if not ui_alive then return end
    open_pwd_panel("", true)
end

--[[
热点行点击（按行号换算当前页的热点下标）

@local
@function on_row_click
@param number i 行号（1~PAGE_SIZE）
]]
local function on_row_click(i)
    if not ui_alive then return end
    local ap = scan_list[(scan_page - 1) * PAGE_SIZE + i]
    if ap then open_pwd_panel(ap.ssid, false) end
end

--[[
热点行点击回调工厂（避免在循环内直接写匿名函数捕获循环变量）

@local
@function make_row_click
@param number i 行号
@return function 点击回调
]]
local function make_row_click(i)
    return function() on_row_click(i) end
end

--[[
上一页 / 下一页

@local
@function on_prev_page
@function on_next_page
]]
local function on_prev_page()
    if not ui_alive or scan_page <= 1 then return end
    scan_page = scan_page - 1
    render_list()
end

local function on_next_page()
    if not ui_alive then return end
    local pages = math.ceil(#scan_list / PAGE_SIZE)
    if scan_page < pages then
        scan_page = scan_page + 1
        render_list()
    end
end

--[[
WiFi 扫描按钮点击：触发扫描

@local
@function on_scan_click
]]
local function on_scan_click()
    if not ui_alive then return end
    if status_label then
        status_label:set_text("扫描中...")
        status_label:set_color(theme.C.t2)
    end
    wlan.scan()
end

--[[
WiFi 扫描完成回调：缓存全部结果并回到第 1 页

@local
@function on_scan_done
]]
local function on_scan_done()
    if not ui_alive then return end
    local list = wlan.scanResult() or {}
    scan_list = {}
    for _, ap in ipairs(list) do
        if ap.ssid and ap.ssid ~= "" then
            scan_list[#scan_list + 1] = { ssid = ap.ssid, rssi = ap.rssi }
        end
    end
    scan_page = 1
    refresh_status()
    render_list()
end

--[[
WiFi 状态更新回调（STATUS_WIFI_UPDATED）

@local
@function on_status_wifi_updated
@param connected boolean 是否已连接
@param ssid string WiFi 名称
@param level number 信号等级
@param rssi number 信号强度 dBm
]]
local function on_status_wifi_updated(connected, ssid, level, rssi)
    wifi_connected = (connected == true)
    cur_ssid = tostring(ssid or "")
    cur_rssi = rssi or 0
    refresh_status()
    render_list()
end

--[[
创建 WiFi 页面 UI（单页：状态行 + 操作行 + 可点击热点列表）

@local
@function create_ui
]]
local function create_ui()
    local ctx = theme.page({ title = "WiFi", on_back = on_back_click })
    main_container = ctx.base

    local X, W, Y = ctx.x, ctx.w, ctx.y

    -- 状态行
    status_label = theme.label(ctx.base, {
        x = X, y = Y, w = W, h = STATUS_H,
        text = "当前: --", px_size = 16, color = theme.C.t3,
    })

    -- 操作行：扫描 + 手动输入（左），翻页（右）
    local op_y = Y + STATUS_H + 4
    theme.ghost(ctx.base, {
        x = X, y = op_y, w = 130, h = OP_H,
        text = "扫描周边 WiFi", on_click = on_scan_click,
    })
    theme.ghost(ctx.base, {
        x = X + 136, y = op_y, w = 90, h = OP_H,
        text = "手动输入", on_click = on_manual_click,
    })

    local btn_w = 32
    local pg_x = X + W - (btn_w * 2 + 44 + 8)
    theme.ghost(ctx.base, {
        x = pg_x, y = op_y, w = btn_w, h = OP_H,
        text = "<", on_click = on_prev_page,
    })
    page_label = theme.label(ctx.base, {
        x = pg_x + btn_w + 4, y = op_y, w = 44, h = OP_H,
        text = "0/0", px_size = 16, color = theme.C.t2,
        align = airui.TEXT_ALIGN_CENTER,
    })
    theme.ghost(ctx.base, {
        x = pg_x + btn_w + 48, y = op_y, w = btn_w, h = OP_H,
        text = ">", on_click = on_next_page,
    })

    -- 热点列表（固定 3 行，复用于分页）
    local list_y = op_y + OP_H + 6
    list_rows = {}
    for i = 1, PAGE_SIZE do
        local ry = list_y + (i - 1) * (ROW_H + ROW_GAP)
        -- 点击贯通：行容器与行内三个文字标签绑同一去重回调
        local tap = theme.click_once(make_row_click(i))
        local row = theme.card(ctx.base, { x = X, y = ry, w = W, h = ROW_H, on_click = tap })
        list_rows[i] = {
            row = row,
            ssid = theme.label(row, {
                x = 12, y = 11, w = 240, h = 20, text = "--", px_size = 16,
                color = theme.C.t1, on_click = tap,
            }),
            rssi = theme.label(row, {
                x = 258, y = 11, w = 90, h = 20, text = "--", px_size = 16,
                color = theme.C.t2, align = airui.TEXT_ALIGN_CENTER, on_click = tap,
            }),
            state = theme.label(row, {
                x = 350, y = 11, w = 102, h = 20, text = "", px_size = 16,
                color = theme.C.t3, align = airui.TEXT_ALIGN_RIGHT, on_click = tap,
            }),
        }
    end

    refresh_status()
    render_list()

    -- 主动查询一次网络状态
    sys.publish("NETWORK_STATUS_QUERY")
end

--[[
窗口创建回调

@local
@function on_create
]]
local function on_create()
    log.info("wifi_win", "[UI-MARK] WiFi 页 v3.0 已加载（热点列表可点击 + 密码弹窗）")
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
    -- 先销毁键盘与弹窗（需在输入框失效之前取到其绑定的键盘）
    destroy_keyboard()
    destroy_pwd_panel()
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    status_label, page_label = nil, nil
    list_rows = {}
    pwd_mask, pwd_panel, pwd_title = nil, nil, nil
    pwd_ssid_input, pwd_pwd_input = nil, nil
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
