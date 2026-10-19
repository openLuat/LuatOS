--[[
@module  ui_wifi
@summary WiFi 配网页：扫描热点 → 选网 → 屏上输密码 → 保存并连接
@version 2.0
@date    2026.10.16
@usage
    sys.publish("OPEN_WIFI_WIN")

说明
1. 凭据存 fskv（wifi_ssid / wifi_pwd），由 app_net.set_wifi 写入并立即生效，
   掉电重启后自动连接，不写死在代码里；
2. 布局坐标全部是**设计坐标**（基准 800×480，见 ui_theme），用 S.DW / S.DH 计算，
   组件内部按屏幕比例换算，5 寸 800×480 与 7/9/10 寸 1024×600 共用同一份布局；
3. 只使用 ui_kit 组件（page / card / label / button / ghost_button），
   颜色只取 ui_theme.COLOR 的语义名，不写死十六进制；
4. 信号强度用三档表达：强=OK / 中=WARN / 弱=TEXT_WEAK，行左侧配 WIFI 图标（LVGL 内置 symbol）；
   "已连接"用 OK 色小字、"已保存"用 PRIMARY 色小字；
5. 扫描是阻塞操作（要等 WLAN_SCAN_DONE），必须放在 task 里跑，不能挂在点击回调上；
6. 注意：扫描结果只有 ssid + rssi（app_net.scan_wifi 只透传这两个字段），
   所以"加密 / 开放"只能对**已保存凭据**判断，其余热点不猜（要每行显示加密方式，
   需要 app_net 透传 authmode，本页面不自行调 wlan 接口）。
]]

local exwin   = require "exwin"
local app_net = require "app_net"
local ui      = require "ui_kit"
local T       = require "ui_theme"

local C, F, S, G = T.COLOR, T.FONT, T.SCREEN, T.GAP

local win_id, page
local view                       -- list | input
local current_ssid, input_pwd = nil, ""
local scanning = false
local pwd_label, pwd_count_label
local hint_label, info_saved_value, info_conn_value

-- ===== 设计坐标布局（基准 800×480，禁止用 S.W / S.H 参与布局）=====

local CARD_W   = S.DW - G.M * 2      -- 760
local LIST_Y   = 100                 -- 扫描结果区起始 y（信息卡 8..84 + 提示行 80..96）
local ROW_W    = CARD_W              -- 每行白卡宽
local ROW_H    = 48
local ROW_GAP  = 6
local MAX_SHOW = 5                   -- 每页最多列 5 个热点（多出来的翻页看）
local page_idx = 1                   -- 当前页（1 起）
local list_cache, hint_cache         -- 最近一次扫描结果，翻页时用同一份数据重绘
local BTN_Y    = 368                 -- 底部操作栏（5 行热点底边 364，栏底 412，都留出空隙）
local BTN_H    = 44

-- 键盘字符集：40 个键，排成 10 列 × 4 行
local KEYS      = "1234567890abcdefghijklmnopqrstuvwxyz.-_@#"
local KEY_COLS  = 10
local KEY_GAP   = 6
local KEY_H     = 44
local KEY_Y     = 176
local MAX_PWD_LEN = 32

-- ===== 状态与小工具 =====

--- WiFi 网卡是否已连上（已拿到 IP）
local function conn_state()
    if not socket.LWIP_STA then return false, nil end
    local s = app_net.get(socket.LWIP_STA)
    if s and s.ready and s.ip then return true, s.ip end
    return false, nil
end

--- 页眉副标题：只表达"当前状态"
local function status_text()
    if scanning then return "扫描中…" end
    local connected, ip = conn_state()
    if connected then return "已连接 " .. tostring(ip) end
    return "未连接"
end

--- 信号强度三档（文字 + 语义色）
local function strength_of(rssi)
    rssi = tonumber(rssi) or -127
    if rssi >= -60 then return "强", C.OK end
    if rssi >= -75 then return "中", C.WARN end
    return "弱", C.TEXT_WEAK
end

--- 已保存凭据的展示文本；密码是否存在 → 加密 / 开放
local function saved_text(ssid, pwd)
    if not ssid or ssid == "" then return "无（点下面热点配网）" end
    local has_pwd = pwd ~= nil and #tostring(pwd) > 0
    return tostring(ssid) .. (has_pwd and " · 加密" or " · 开放")
end

--- 刷新"状态类"文字（页眉 + 信息卡行），不重建页面
local function refresh_status()
    if not (page and info_conn_value) then return end
    page.set_subtitle(status_text())

    local connected, ip = conn_state()
    if connected then
        info_conn_value:set_text("已连接 · " .. tostring(ip))
    else
        info_conn_value:set_text("未连接（保存后自动重连）")
    end
    -- airui 若没有 set_color 就保持原色，不能因为配色把刷新打断
    pcall(function() info_conn_value:set_color(connected and C.OK or C.TEXT_WEAK) end)

    local ssid_saved, pwd_saved = app_net.get_wifi_cred()
    if info_saved_value then
        info_saved_value:set_text(saved_text(ssid_saved, pwd_saved))
    end
end

-- ===== 视图：热点列表 =====

local closing = false

--- 立即销毁本页控件（不依赖 exwin 的 on_destroy 是否被调用成功）
local function destroy_page()
    if page then
        pcall(page.destroy)
        page = nil
    end
    pwd_label, pwd_count_label = nil, nil
    hint_label, info_saved_value, info_conn_value = nil, nil, nil
end

local function go_back()
    if closing then return end
    closing = true

    log.info("ui_wifi", "返回：win_id =", tostring(win_id),
        "active =", tostring(exwin.is_active(win_id)),
        "depth =", tostring(exwin.depth()))

    destroy_page()

    local ok, err = pcall(exwin.close, win_id)
    log.info("ui_wifi", "exwin.close 结果", ok, tostring(err),
        "depth =", tostring(exwin.depth()))

    -- close 没生效 → 直接销毁除首页外的所有窗口
    if (win_id and exwin.is_active(win_id)) or exwin.depth() > 1 then
        log.warn("ui_wifi", "close 未生效，改用 exwin.return_idle() 回首页")
        pcall(exwin.return_idle)
    end

    win_id = nil
    closing = false
end

local function render_list(items, hint)
    items = items or {}
    -- 翻页时用同一份扫描结果重绘，不再重新扫描
    list_cache, hint_cache = items, hint
    view = "list"

    -- 切回列表视图：密码视图的控件句柄全部作废
    pwd_label, pwd_count_label = nil, nil

    if page then page.destroy() end
    page = ui.page({
        title    = "WiFi",
        subtitle = status_text(),
        on_back  = go_back,
        -- 诊断：点页面空白处会打这条日志。用来区分"触摸没进页面"还是"只有按钮不响应"
        on_body_click = function() log.info("ui_wifi", "页面空白处收到点击（触摸正常）") end,
    })

    local ssid_saved, pwd_saved = app_net.get_wifi_cred()
    local connected = conn_state()

    -- ===== 顶部信息卡：已保存凭据 + 连接状态（同类信息合并一张卡）=====
    local info = ui.card({ parent = page.body, x = G.M, y = 8, w = CARD_W, h = 76, border = C.BORDER })

    ui.label({
        parent = info, x = G.M, y = 8, w = 180, h = 26,
        text = "已保存热点", size = F.TINY, color = C.TEXT_WEAK,
    })
    info_saved_value = ui.label({
        parent = info, x = G.M + 180, y = 6, w = CARD_W - G.M * 2 - 180, h = 28,
        text = "", size = F.SMALL, color = C.TEXT, align = airui.TEXT_ALIGN_RIGHT,
    })

    ui.label({
        parent = info, x = G.M, y = 42, w = 180, h = 26,
        text = "连接状态", size = F.TINY, color = C.TEXT_WEAK,
    })
    info_conn_value = ui.label({
        parent = info, x = G.M + 180, y = 40, w = CARD_W - G.M * 2 - 180, h = 28,
        text = "", size = F.SMALL, color = C.TEXT_WEAK, align = airui.TEXT_ALIGN_RIGHT,
    })

    hint_label = ui.label({
        parent = page.body, x = G.M, y = 80, w = CARD_W, h = 16,
        text = hint or "", size = F.TINY, color = C.TEXT_WEAK,
    })

    -- ===== 扫描结果：每页最多 MAX_SHOW 个，超出的翻页看 =====
    local total = #items
    local pages = math.max(1, math.ceil(total / MAX_SHOW))
    if page_idx > pages then page_idx = pages end
    if page_idx < 1 then page_idx = 1 end
    local first = (page_idx - 1) * MAX_SHOW + 1
    local last  = math.min(first + MAX_SHOW - 1, total)

    for i = first, last do
        local item = items[i]

        local level, level_color = strength_of(item.rssi)
        local tag, tag_color
        if ssid_saved and ssid_saved ~= "" and item.ssid == ssid_saved then
            local has_pwd = pwd_saved ~= nil and #tostring(pwd_saved) > 0
            if connected then
                tag, tag_color = "已连接", C.OK
            else
                tag, tag_color = "已保存", C.PRIMARY
            end
            tag = tag .. (has_pwd and " · 加密" or " · 开放")
        end

        local tap = ui.tap_once(function()
            current_ssid = item.ssid
            input_pwd = (ssid_saved == item.ssid) and tostring(pwd_saved or "") or ""
            view = "input"
            sys.publish("WIFI_OPEN_INPUT")
        end)

        local row = ui.card({
            parent = page.body, x = G.M, y = LIST_Y + (i - first) * (ROW_H + ROW_GAP),
            w = ROW_W, h = ROW_H, border = C.BORDER,
            on_click = tap,
        })

        -- 图标：LVGL 内置 symbol，配色跟随信号强度（固件无此 symbol 时自动跳过）
        local sym = airui.SYMBOL_WIFI
        if sym then
            ui.label({
                parent = row, x = 12, y = math.floor((ROW_H - F.NORMAL) / 2), w = 28, h = F.NORMAL + 4,
                symbol = sym, size = F.NORMAL, color = level_color,
                on_click = tap,
            })
        end

        ui.label({
            parent = row, x = 46, y = math.floor((ROW_H - F.NORMAL) / 2), w = 288, h = F.NORMAL + 4,
            text = tostring(item.ssid or ""), size = F.NORMAL, color = C.TEXT,
            on_click = tap,
        })

        if tag then
            ui.label({
                parent = row, x = 336, y = math.floor((ROW_H - F.TINY) / 2), w = 184, h = F.TINY + 4,
                text = tag, size = F.TINY, color = tag_color,
                on_click = tap,
            })
        end

        ui.label({
            parent = row, x = 520, y = math.floor((ROW_H - F.SMALL) / 2), w = 110, h = F.SMALL + 4,
            text = level .. "信号", size = F.SMALL, color = level_color,
            align = airui.TEXT_ALIGN_RIGHT,
            on_click = tap,
        })
        ui.label({
            parent = row, x = 634, y = math.floor((ROW_H - F.TINY) / 2), w = 110, h = F.TINY + 4,
            text = tostring(item.rssi or "--") .. " dBm", size = F.TINY, color = C.TEXT_WEAK,
            align = airui.TEXT_ALIGN_RIGHT,
            on_click = tap,
        })
    end

    -- 空态：区分"正在扫描"和"真的没扫到"
    if #items == 0 then
        local empty = ui.card({ parent = page.body, x = G.M, y = LIST_Y, w = ROW_W, h = 120, border = C.BORDER })
        -- 文字左右各缩 2px：与卡片同宽（x=0, w=ROW_W）会触发卡片画滚动条
        ui.label({
            parent = empty, x = 2, y = 28, w = ROW_W - 4, h = F.NORMAL + 4,
            text = scanning and "正在扫描附近热点…" or "没有扫描到热点",
            size = F.NORMAL, color = C.TEXT_SUB, align = airui.TEXT_ALIGN_CENTER,
        })
        if not scanning then
            ui.label({
                parent = empty, x = 2, y = 64, w = ROW_W - 4, h = F.TINY + 4,
                text = "点下面「重新扫描」再试，或检查板载天线",
                size = F.TINY, color = C.TEXT_WEAK, align = airui.TEXT_ALIGN_CENTER,
            })
        end
    end

    -- ===== 操作栏 =====
    ui.button({
        parent = page.body, x = G.M, y = BTN_Y, w = 240, h = BTN_H, text = "重新扫描",
        on_click = function() sys.publish("WIFI_RESCAN") end,
    })
    ui.ghost_button({
        parent = page.body, x = G.M + 260, y = BTN_Y, w = 220, h = BTN_H, text = "清除凭据",
        text_color = C.DANGER,
        on_click = function()
            app_net.clear_wifi_cred()
            page.toast("已清除 WiFi 凭据")
            sys.publish("WIFI_RESCAN")
        end,
    })

    -- ===== 翻页：热点超过一页时才出现（放操作栏右侧空白处）=====
    if pages > 1 then
        local pw, pgap = 80, 6
        local bx = 508        -- 「清除凭据」右边界 500，留 8px 间隙

        local function mkpage(x, text, delta, disabled)
            ui.ghost_button({
                parent = page.body, x = x, y = BTN_Y, w = pw, h = BTN_H, text = text,
                color      = disabled and C.BG or C.PRIMARY_SOFT,
                text_color = disabled and C.TEXT_WEAK or C.PRIMARY,
                on_click   = function()
                    if disabled then return end
                    page_idx = page_idx + delta
                    render_list(list_cache, hint_cache)
                end,
            })
        end

        mkpage(bx, "上一页", -1, page_idx <= 1)
        ui.label({
            parent = page.body, x = bx + pw + pgap,
            y = BTN_Y + math.floor((BTN_H - F.SMALL) / 2), w = 72, h = F.SMALL + 4,
            text = string.format("%d / %d", page_idx, pages),
            size = F.SMALL, color = C.TEXT_SUB, align = airui.TEXT_ALIGN_CENTER,
        })
        mkpage(bx + pw + pgap + 72 + pgap, "下一页", 1, page_idx >= pages)
    end

    refresh_status()
end

-- ===== 视图：密码输入 =====

local function refresh_pwd_label()
    if not pwd_label then return end
    if #input_pwd > 0 then
        pwd_label:set_text(string.rep("*", #input_pwd))
    else
        pwd_label:set_text("（未输入，按开放热点连接）")
    end
    if pwd_count_label then
        pwd_count_label:set_text(string.format("%d / %d", #input_pwd, MAX_PWD_LEN))
    end
end

local function render_input()
    view = "input"

    -- 切到密码视图：列表视图的控件句柄全部作废
    hint_label, info_saved_value, info_conn_value = nil, nil, nil

    local ssid_saved = app_net.get_wifi_cred()

    if page then page.destroy() end
    page = ui.page({
        title    = "WiFi 密码",
        subtitle = tostring(current_ssid or ""),
        on_back  = function()
            current_ssid, input_pwd = nil, ""
            sys.publish("WIFI_BACK_LIST")
        end,
    })

    -- ===== 目标热点 =====
    local card = ui.card({ parent = page.body, x = G.M, y = 8, w = CARD_W, h = 70, border = C.BORDER })
    ui.label({
        parent = card, x = G.M, y = 12, w = CARD_W - G.M * 2, h = 18,
        text = "目标热点", size = F.TINY, color = C.TEXT_WEAK,
    })
    ui.label({
        parent = card, x = G.M, y = 32, w = CARD_W - G.M * 2, h = F.NORMAL + 4,
        text = tostring(current_ssid or ""), size = F.NORMAL, color = C.TEXT,
    })

    local hint = (ssid_saved ~= nil and ssid_saved == current_ssid)
        and "该热点已有保存的凭据，密码已回填，可直接连接"
        or  "加密热点请输入密码；开放热点留空即可"
    ui.label({
        parent = page.body, x = G.M, y = 84, w = CARD_W, h = 18,
        text = hint, size = F.TINY, color = C.TEXT_WEAK,
    })

    -- ===== 密码显示 =====
    local box = ui.card({ parent = page.body, x = G.M, y = 110, w = CARD_W, h = 56, border = C.BORDER })
    pwd_label = ui.label({
        parent = box, x = G.M, y = 16, w = CARD_W - 200, h = F.NORMAL + 4,
        text = "", size = F.NORMAL, color = C.PRIMARY,
    })
    pwd_count_label = ui.label({
        parent = box, x = CARD_W - 160, y = 20, w = 140, h = F.TINY + 4,
        text = "", size = F.TINY, color = C.TEXT_WEAK,
        align = airui.TEXT_ALIGN_RIGHT,
    })
    refresh_pwd_label()

    -- ===== 屏上键盘（40 键，做成 10 列 × 4 行的按钮）=====
    local key_w = math.floor((CARD_W - KEY_GAP * (KEY_COLS - 1)) / KEY_COLS)
    local used  = key_w * KEY_COLS + KEY_GAP * (KEY_COLS - 1)
    local key_x = G.M + math.floor((CARD_W - used) / 2)

    for i = 1, #KEYS do
        local ch    = KEYS:sub(i, i)
        local col   = (i - 1) % KEY_COLS
        local row_i = math.floor((i - 1) / KEY_COLS)
        ui.button({
            parent = page.body,
            x = key_x + col * (key_w + KEY_GAP),
            y = KEY_Y + row_i * (KEY_H + KEY_GAP),
            w = key_w, h = KEY_H, text = ch,
            color = C.CARD, text_color = C.TEXT,
            on_click = function()
                if #input_pwd < MAX_PWD_LEN then
                    input_pwd = input_pwd .. ch
                    refresh_pwd_label()
                end
            end,
        })
    end

    -- ===== 操作栏 =====
    ui.ghost_button({
        parent = page.body, x = G.M, y = BTN_Y, w = 160, h = BTN_H, text = "删除",
        on_click = function()
            input_pwd = input_pwd:sub(1, -2)
            refresh_pwd_label()
        end,
    })
    ui.ghost_button({
        parent = page.body, x = 190, y = BTN_Y, w = 140, h = BTN_H, text = "清空",
        on_click = function()
            input_pwd = ""
            refresh_pwd_label()
        end,
    })
    ui.ghost_button({
        parent = page.body, x = 340, y = BTN_Y, w = 140, h = BTN_H, text = "取消",
        on_click = function()
            current_ssid, input_pwd = nil, ""
            sys.publish("WIFI_BACK_LIST")
        end,
    })
    ui.button({
        parent = page.body, x = 490, y = BTN_Y, w = 270, h = BTN_H, text = "保存并连接",
        on_click = function() sys.publish("WIFI_CONNECT") end,
    })
end

-- ===== 事件 =====

-- 扫描：阻塞到扫描完成，必须放到 task 里，扫描期间页眉显示"扫描中…"
local function scan_task()
    scanning = true
    if page then
        page.set_subtitle("扫描中…")
        if hint_label then hint_label:set_text("正在扫描附近热点…") end
    end

    local items = app_net.scan_wifi()

    scanning = false
    if not win_id then return end
    if view == "list" then
        page_idx = 1        -- 新一轮扫描结果从第一页开始看
        render_list(items, string.format("扫描到 %d 个热点，点一下开始配网", #items))
    end
end

-- 重新扫描：已在列表页就只更新提示（不闪屏），从密码页回来则先重建空列表
local function rescan()
    scanning = true
    if view == "list" and page then
        page.set_subtitle("扫描中…")
        if hint_label then hint_label:set_text("正在扫描附近热点…") end
    else
        render_list({}, "正在扫描附近热点…")
    end
    sys.taskInit(scan_task)
end

-- 配网：保存凭据并让 exnetif 重连（set_priority_order 是增量更新，不用重启）
local function connect_task()
    local ssid = current_ssid
    local pwd  = input_pwd
    current_ssid, input_pwd = nil, ""

    if not ssid or ssid == "" then
        sys.publish("WIFI_BACK_LIST")
        return
    end

    app_net.set_wifi(ssid, pwd)

    scanning = true
    sys.wait(200)
    local items = app_net.scan_wifi()
    scanning = false

    if not win_id then return end
    page_idx = 1
    render_list(items, "已保存 " .. ssid .. "，正在连接…（看页眉的连接状态）")
end

local function on_create()
    sys.subscribe("WIFI_RESCAN", rescan)
    sys.subscribe("WIFI_OPEN_INPUT", render_input)
    sys.subscribe("WIFI_BACK_LIST", rescan)
    sys.subscribe("WIFI_CONNECT", function() sys.taskInit(connect_task) end)
    sys.subscribe("APP_NET_CHANGED", refresh_status)

    -- 先建页面（显示"正在扫描"），再跑阻塞扫描，避免这段时间黑屏
    rescan()
end

local function on_destroy()
    log.info("ui_wifi", "on_destroy 开始")
    if page then
        pcall(page.destroy)
        page = nil
    end

    pcall(sys.unsubscribe, "WIFI_RESCAN")
    pcall(sys.unsubscribe, "WIFI_OPEN_INPUT")
    pcall(sys.unsubscribe, "WIFI_BACK_LIST")
    pcall(sys.unsubscribe, "WIFI_CONNECT")
    pcall(sys.unsubscribe, "APP_NET_CHANGED")
    log.info("ui_wifi", "on_destroy 完成")

    win_id, view, current_ssid, input_pwd = nil, "list", nil, ""
    scanning = false
    pwd_label, pwd_count_label = nil, nil
    hint_label, info_saved_value, info_conn_value = nil, nil, nil
end

sys.subscribe("OPEN_WIFI_WIN", function()
    win_id = exwin.open({
        on_create     = on_create,
        on_destroy    = on_destroy,
        on_get_focus  = function() end,
        on_lose_focus = function() end,
    })
end)
