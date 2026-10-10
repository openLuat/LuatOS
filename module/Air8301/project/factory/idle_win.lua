--[[
@module  idle_win
@summary 主页·时间与天气仪表盘（8301出厂固件·业务模式）
@version 1.0
@date    2026.10.09
@author  江访

@usage
界面范式（方案A：顶部状态条 + 中部仪表区 + 底部 Dock 分区导航）：
本页由原「2×2 四张实时状态卡」重构为「时间 + 天气」仪表盘，信息架构如下：
  顶部状态条 —— 产品名（theme.BRAND） + 时间
  左上卡片   —— 当前时间（大号时钟 + 秒 + 日期 + 星期）
  右上卡片   —— 天气（城市 / 当前温度 / 天气现象 / 湿度与风 / 今日高低温）
  底部状态条 —— 联网方式 / 4G 信号等级 / 本机 IP 三格
  底部 Dock  —— 主页 / 通信 / IO / 系统 四分区切换（当前分区琥珀高亮）

数据来源（全部为既有消息接口，本页只做订阅展示，不做业务逻辑）：
  STATUS_SIGNAL_UPDATED(level)            4G 信号等级（net_drv 发布）
  STATUS_WIFI_UPDATED(conn,ssid,lv,rssi)  WiFi 连接状态（net_drv 发布）
  STATUS_ETH_UPDATED(e1,ip1,e2,ip2)       以太网 1/2 连接与 IP（net_drv 发布）
  NET_ACTIVE_UPDATED(type,adapter,name)   多网融合当前生效链路（net_drv 发布）
  NETWORK_STATUS_QUERY                    打开页面时主动查询一次网络状态
  WEATHER_UPDATE(state)                   时间/天气数据源（weather_app 发布）
  WEATHER_QUERY                           打开页面时唤醒天气任务立即刷新

本地数据来源（无需订阅）：
  时间 / 日期 / 星期 —— os.date()（由 time_sync 的 NTP 授时保证准确）
  本机 IP            —— socket.localIP(socket.dft())

@note
  1) 本页只承载 Air8301 实际支持的功能，不引入 8601 等大屏机型才有的应用；
  2) 原四张状态卡（蜂窝网络 / RS485-1 / 继电器 / DO 输出）按需求移除，
     其入口分别由「通信」分区页与「IO」分区页承接，功能无损；
  3) 天气数据源为 Open-Meteo（免费、无需 Key），未定位或断网时天气区显示 "--"，
     取到数据后自动刷新；城市名依赖基站定位反查，定位失败时显示 "--"；
  4) 底部「联网方式」与「通信 → 多网融合」页保持一致：优先显示 exnetif 多网融合调度的
     当前生效链路（订阅 NET_ACTIVE_UPDATED）；仅在未取到该值时，才退回「按网卡链路判定」
     （网口1 → 网口2 → WiFi → 4G）的原有逻辑。
]]

local theme = require "ui_theme"
require "theme"   -- 设置全局 T（提供按键音兜底 T.with_beep）

local win_id = nil
local main_container
local status                                          -- 状态条句柄（time）
local clock_timer = nil

-- 时间卡片标签句柄
local lbl_clock, lbl_sec, lbl_date
-- 天气卡片标签句柄
local lbl_city, lbl_temp, lbl_wtext, lbl_wdetail, lbl_wrange
-- 底部设备状态条标签句柄
local lbl_net, lbl_sig, lbl_ip

-- 当前分区标识（与 ui_theme.NAV 的 key 对应）与切换防抖标志
local NAV_KEY = "overview"
local nav_busy = false

-- 日期文本缓存：仅在日期变化时重绘，避免每秒刷新日期标签
local last_date = ""

-- 设备网络状态缓存（由 net_drv 的消息刷新）
-- active：多网融合当前生效链路名（NET_ACTIVE_UPDATED），为空或「查询中」时退回各网卡链路判定
local dev = { e1 = 0, ip1 = "", e2 = 0, ip2 = "", wifi = false, ssid = "", active = "" }

-- 布局常量（内容区 464×182：上排 126 + 间距 6 + 下排 50 = 182）
local GAP        = 6
local TIME_W     = 220   -- 时间卡片宽
local WEATHER_W  = 238   -- 天气卡片宽（220 + 6 + 238 = 464）
local TOP_H      = 126   -- 上排高
local BOTTOM_H   = 50    -- 底部状态条高
local CELL_W     = 150   -- 底部单格宽（150×3 + 6×2 = 462 ≤ 464）

-- 中文星期
local WEEK_CN = { "日", "一", "二", "三", "四", "五", "六" }

--[[取中文星期文本（如「星期五」）

@local
@function weekday_cn
@return string
]]
local function weekday_cn()
    local w = tonumber(os.date("%w")) or 0
    return "星期" .. WEEK_CN[w + 1]
end

--[[温度格式化：数值 →「26℃」，非法值 →「--」

@local
@function fmt_temp
@param v number 温度（℃）
@return string
]]
local function fmt_temp(v)
    if type(v) ~= "number" then return "--" end
    return string.format("%.0f", v) .. theme.CHAR.deg
end

-- ==================== 时钟 ====================

--[[刷新时间卡片与状态条时钟（每秒触发）

@local
@function refresh_clock
]]
local function refresh_clock()
    -- 仅在本页可见（栈顶）时刷新，避免被分区页覆盖后仍反复重绘（首页为常驻宿主，故必须加此判断）
    if not exwin.is_active(win_id) then return end
    local now = os.date("%H:%M")
    if lbl_clock then lbl_clock:set_text(now) end
    if status and status.time then status.time:set_text(now) end
    if lbl_sec then
        lbl_sec:set_text(string.format("%02d 秒", tonumber(os.date("%S")) or 0))
    end
    if lbl_date then
        local d = os.date("%Y年%m月%d日") .. " " .. weekday_cn()
        if d ~= last_date then
            last_date = d
            lbl_date:set_text(d)
        end
    end
end

-- ==================== 设备状态条 ====================

--[[读取当前默认网卡的 IPv4 地址

@local
@function current_ip
@return string|nil IP 地址；未就绪返回 nil
]]
local function current_ip()
    local ok, ip = pcall(socket.localIP, socket.dft())
    if ok and type(ip) == "string" and ip ~= "" and ip ~= "0.0.0.0" then
        return ip
    end
    return nil
end

--[[重算「联网方式」并刷新底部状态条（联网方式 / 本机 IP）

@local
@function recompute_net
]]
local function recompute_net()
    local mode
    -- 多网融合（exnetif）模式下，非当前生效的网卡同样保持连接（exnetif 仅把默认网卡
    -- socket.dft() 切到最高优先级可用网卡），因此不能按「哪张网卡有 IP 就用哪张」判断，
    -- 否则会出现「多网融合页显示 WiFi、主页却显示网口1」的不一致。
    -- 规则：优先采用多网融合调度的当前生效链路；未取到（空值 / 查询中）再退回原有链路判定。
    if dev.active ~= "" and dev.active ~= "查询中" then
        mode = (dev.active == "无可用网络") and "未连接" or dev.active
    elseif dev.e1 > 0 then
        mode = "网口1"
    elseif dev.e2 > 0 then
        mode = "网口2"
    elseif dev.wifi then
        mode = "WiFi"
    elseif socket.adapter(socket.dft()) then
        mode = "4G"
    else
        mode = "未连接"
    end
    if lbl_net then lbl_net:set_text(mode) end
    if lbl_ip then lbl_ip:set_text(current_ip() or "--") end
end

--[[以太网状态更新（net_drv → STATUS_ETH_UPDATED）

@local
@function on_eth_updated
@param e1 number 以太网1连接状态(0/1)
@param ip1 string 以太网1的IP
@param e2 number 以太网2连接状态(0/1)
@param ip2 string 以太网2的IP
]]
local function on_eth_updated(e1, ip1, e2, ip2)
    if not exwin.is_active(win_id) then return end
    dev.e1, dev.ip1 = e1 or 0, ip1 or ""
    dev.e2, dev.ip2 = e2 or 0, ip2 or ""
    recompute_net()
end

--[[WiFi 状态更新（net_drv → STATUS_WIFI_UPDATED）

@local
@function on_wifi_updated
@param connected boolean 是否已连接
@param ssid string WiFi 名称
@param level number 信号等级
@param rssi number 信号强度(dBm)
]]
local function on_wifi_updated(connected, ssid, level, rssi)
    if not exwin.is_active(win_id) then return end
    dev.wifi = connected and true or false
    dev.ssid = ssid or ""
    recompute_net()
end

--[[4G 信号等级更新（net_drv → STATUS_SIGNAL_UPDATED）

@local
@function on_signal_updated
@param level number 信号等级(0~5)，0 表示无服务
]]
local function on_signal_updated(level)
    if not exwin.is_active(win_id) or not lbl_sig then return end
    if level == nil or level == 0 then
        lbl_sig:set_text("无服务")
        lbl_sig:set_color(theme.SEM.danger)
    else
        lbl_sig:set_text(tostring(level) .. "级")
        lbl_sig:set_color(theme.C.t1)
    end
end

--[[多网融合当前生效链路更新（net_drv → NET_ACTIVE_UPDATED）

exnetif 多网融合调度的结果：有可用网络时给出网卡中文名，全部断网时给出「无可用网络」。

@local
@function on_net_active
@param net_type string|nil 网卡类型字符串（"WiFi" / "Ethernet" / "4G" 等）
@param adapter number 网卡编号（-1 表示全部断网）
@param name string 网卡中文名（网口1 / 网口2 / WiFi / 4G / 无可用网络 / 查询中）
]]
local function on_net_active(net_type, adapter, name)
    dev.active = name or ""
    -- 本页为常驻宿主：被分区页覆盖（非激活）时仍需更新缓存，回到本页后 on_get_focus
    -- 才能立即显示正确的联网方式
    if exwin.is_active(win_id) then recompute_net() end
end

-- ==================== 天气刷新 ====================

--[[天气数据更新（weather_app → WEATHER_UPDATE）

@local
@function on_weather_update
@param st table weather_app 发布的状态表
]]
local function on_weather_update(st)
    if not exwin.is_active(win_id) or type(st) ~= "table" then return end

    -- 城市名独立于天气请求（来自基站定位反查），先更新
    if lbl_city then
        lbl_city:set_text((type(st.city) == "string" and st.city ~= "") and st.city or "--")
    end

    if not st.ok then
        -- 尚未成功取到数据：保持占位显示
        if lbl_temp then lbl_temp:set_text("--") end
        if lbl_wtext then lbl_wtext:set_text("获取中") end
        if lbl_wdetail then lbl_wdetail:set_text("湿度 --" .. theme.CHAR.sep .. " 风 --") end
        if lbl_wrange then lbl_wrange:set_text("今日 -- ~ --") end
        return
    end

    if lbl_temp then lbl_temp:set_text(fmt_temp(st.temp)) end
    if lbl_wtext then lbl_wtext:set_text(st.text or "--") end

    local hum = (type(st.humidity) == "number") and string.format("%.0f", st.humidity) or "--"
    local wind
    if type(st.wind_level) == "number" and st.wind_level > 0 and st.wind_dir ~= "" then
        wind = st.wind_dir .. "风 " .. tostring(st.wind_level) .. "级"
    else
        wind = "风 --"
    end
    if lbl_wdetail then
        lbl_wdetail:set_text("湿度 " .. hum .. "%" .. theme.CHAR.sep .. " " .. wind)
    end
    if lbl_wrange then
        lbl_wrange:set_text("今日 " .. fmt_temp(st.tmin) .. " ~ " .. fmt_temp(st.tmax))
    end
end

-- ==================== Dock 分区导航 ====================

--[[切换防抖复位：一次切换事务开始时置忙，短暂延时后自动解除

@local
@function reset_nav_busy
]]
local function reset_nav_busy()
    nav_busy = false
end

--[[Dock 分区点击回调（exwin v2.1 事务式切换，杜绝白屏）

切换流程（与旧实现的关键差异）：
  旧：先 close 自己 → 延迟 30ms → 再开目标页。中间窗口栈为空，必然白屏一闪；
      且连点会创建多个页面，导致栈顶错乱、is_active 判定失败（表现为「点不动」）。
  新：不关自己，而是向 exwin 声明「一级菜单切换事务」（宿主 = 本常驻首页），
      再由消息打开目标页；exwin 会在新页创建完成后自动回收宿主的旧子页。
      全程始终有窗口在屏 → 无白屏；页面数恒定 → 不堆积 → 交互不再失效。

@local
@function on_nav
@param key string 目标分区标识
@param msg string 目标分区页的打开消息
]]
local function on_nav(key, msg)
    if key == NAV_KEY or nav_busy then return end
    nav_busy = true
    local host = _G.UIFW_HOST_WIN or win_id
    if host and exwin.begin_menu_switch then
        exwin.begin_menu_switch(host)
    end
    sys.publish(msg)
    sys.timerStart(reset_nav_busy, 400)
end

-- ==================== UI 构建 ====================

--[[创建「时间 + 天气」仪表盘首页

@local
@function create_ui
]]
local function create_ui()
    local ctx = theme.shell({
        title = theme.BRAND,   -- 左上角统一显示「合宙工业网关Air8301」
        active = NAV_KEY,
        on_nav = on_nav,
        time = os.date("%H:%M"),
    })
    main_container = ctx.base
    status = ctx.status

    local x, y = ctx.x, ctx.y

    -- ---------- 左上：时间卡片 ----------
    local card_t = theme.card(main_container, {
        x = x, y = y, w = TIME_W, h = TOP_H,
        border = theme.C.stroke_soft,
    })
    theme.section(card_t, { x = 10, y = 8, w = 160, text = "当前时间" })

    lbl_clock = theme.label(card_t, {
        x = 10, y = 26, w = 140, h = 47,
        text = os.date("%H:%M"), px_size = 44, color = theme.C.t1,
    })
    lbl_sec = theme.label(card_t, {
        x = 150, y = 56, w = 62, h = 19,
        text = "-- 秒", px_size = 16, color = theme.C.t2,
        align = airui.TEXT_ALIGN_RIGHT,
    })
    theme.divider(card_t, { x = 10, y = 82, w = 200, h = 1 })
    last_date = os.date("%Y年%m月%d日") .. " " .. weekday_cn()
    lbl_date = theme.label(card_t, {
        x = 10, y = 90, w = 200, h = 19,
        text = last_date, px_size = 16, color = theme.C.t2,
    })

    -- ---------- 右上：天气卡片（品牌浅蓝底 + 品牌蓝描边，作为主页视觉焦点） ----------
    local wx = x + TIME_W + GAP
    local card_w = theme.card(main_container, {
        x = wx, y = y, w = WEATHER_W, h = TOP_H,
        color = theme.C.brand_soft,
        border = theme.C.brand,
    })
    theme.section(card_w, { x = 10, y = 8, w = 50, text = "天气", color = theme.C.brand_deep })
    lbl_city = theme.label(card_w, {
        x = 62, y = 8, w = WEATHER_W - 72, h = 19,
        text = "--", px_size = 16, color = theme.C.t3,
        align = airui.TEXT_ALIGN_RIGHT,
    })

    lbl_temp = theme.label(card_w, {
        x = 10, y = 26, w = 120, h = 43,
        text = "--", px_size = 40, color = theme.C.primary,
    })
    lbl_wtext = theme.label(card_w, {
        x = 132, y = 38, w = 96, h = 23,
        text = "获取中", px_size = 20, color = theme.SEM.info,
    })
    lbl_wdetail = theme.label(card_w, {
        x = 10, y = 78, w = WEATHER_W - 20, h = 19,
        text = "湿度 --" .. theme.CHAR.sep .. " 风 --", px_size = 16, color = theme.C.t2,
    })
    lbl_wrange = theme.label(card_w, {
        x = 10, y = 100, w = WEATHER_W - 20, h = 19,
        text = "今日 -- ~ --", px_size = 16, color = theme.C.t2,
    })

    -- ---------- 底部：设备状态条（3 格） ----------
    local by = y + TOP_H + GAP
    local bx = { x, x + CELL_W + GAP, x + (CELL_W + GAP) * 2 }

    local cell_net = theme.card(main_container, {
        x = bx[1], y = by, w = CELL_W, h = BOTTOM_H,
        border = theme.C.stroke_soft,
    })
    theme.section(cell_net, { x = 10, y = 6, w = CELL_W - 20, text = "联网方式" })
    lbl_net = theme.label(cell_net, {
        x = 10, y = 24, w = CELL_W - 20, h = 23,
        text = "未连接", px_size = 18, color = theme.C.t1,
    })

    local cell_sig = theme.card(main_container, {
        x = bx[2], y = by, w = CELL_W, h = BOTTOM_H,
        border = theme.C.stroke_soft,
    })
    theme.section(cell_sig, { x = 10, y = 6, w = CELL_W - 20, text = "4G信号" })
    lbl_sig = theme.label(cell_sig, {
        x = 10, y = 24, w = CELL_W - 20, h = 23,
        text = "--", px_size = 18, color = theme.C.t1,
    })

    local cell_ip = theme.card(main_container, {
        x = bx[3], y = by, w = CELL_W, h = BOTTOM_H,
        border = theme.C.stroke_soft,
    })
    theme.section(cell_ip, { x = 10, y = 6, w = CELL_W - 20, text = "本机IP" })
    lbl_ip = theme.label(cell_ip, {
        x = 10, y = 24, w = CELL_W - 20, h = 23,
        text = "--", px_size = 18, color = theme.C.t1,
    })
end

-- ==================== 窗口生命周期 ====================

--[[窗口创建回调

@local
@function on_create
]]
local function on_create()
    log.info("idle_win", "[UI-MARK] 主页仪表盘 v2.0 已加载（时间 + 天气 + 设备状态）")
    create_ui()
    sys.subscribe("STATUS_SIGNAL_UPDATED", on_signal_updated)
    sys.subscribe("STATUS_WIFI_UPDATED", on_wifi_updated)
    sys.subscribe("STATUS_ETH_UPDATED", on_eth_updated)
    sys.subscribe("NET_ACTIVE_UPDATED", on_net_active)
    sys.subscribe("WEATHER_UPDATE", on_weather_update)
    -- 主动查询一次网络状态与天气，避免打开页面时显示占位
    sys.publish("NETWORK_STATUS_QUERY")
    sys.publish("WEATHER_QUERY")
    refresh_clock()
    clock_timer = sys.timerLoopStart(refresh_clock, 1000)
end

--[[窗口销毁回调：释放组件、停表、退订

@local
@function on_destroy
]]
local function on_destroy()
    if clock_timer then
        sys.timerStop(clock_timer)
        clock_timer = nil
    end
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    status = nil
    lbl_clock, lbl_sec, lbl_date = nil, nil, nil
    lbl_city, lbl_temp, lbl_wtext, lbl_wdetail, lbl_wrange = nil, nil, nil, nil, nil
    lbl_net, lbl_sig, lbl_ip = nil, nil, nil
    sys.unsubscribe("STATUS_SIGNAL_UPDATED", on_signal_updated)
    sys.unsubscribe("STATUS_WIFI_UPDATED", on_wifi_updated)
    sys.unsubscribe("STATUS_ETH_UPDATED", on_eth_updated)
    sys.unsubscribe("NET_ACTIVE_UPDATED", on_net_active)
    sys.unsubscribe("WEATHER_UPDATE", on_weather_update)
    if _G.UIFW_HOST_WIN == win_id then _G.UIFW_HOST_WIN = nil end
    win_id = nil
end

--[[窗口获得焦点回调：刷新时钟并重新查询网络与天气

@local
@function on_get_focus
]]
local function on_get_focus()
    refresh_clock()
    recompute_net()
    sys.publish("NETWORK_STATUS_QUERY")
    sys.publish("WEATHER_QUERY")
end

--[[窗口失去焦点回调

@local
@function on_lose_focus
]]
local function on_lose_focus() end

--[[OPEN_IDLE_WIN 消息处理器

@local
@function open_handler
]]
local function open_handler()
    if win_id then
        -- 首页为常驻宿主：已存在时不重复建窗，仅回收其子页回到首页
        if not exwin.is_active(win_id) and exwin.close_children_of then
            exwin.close_children_of(win_id)
        end
        return
    end
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_get_focus = on_get_focus,
        on_lose_focus = on_lose_focus,
    })
    -- 登记为分区切换的常驻宿主（各分区页 Dock 切换时作为 host 引用）
    _G.UIFW_HOST_WIN = win_id
end

sys.subscribe("OPEN_IDLE_WIN", open_handler)
