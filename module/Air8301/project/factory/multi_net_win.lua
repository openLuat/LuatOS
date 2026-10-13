--[[
@module  multi_net_win
@summary 多网融合配置页（优先级排序 + 当前生效链路 + 各网卡状态）（8301出厂固件）
@version 1.0
@date    2026.10.09
@author  江访

@usage
入口：业务模式「通信」分区页（comm_win）第 6 个磁贴「多网融合」→ OPEN_MULTINET_WIN。

页面内容（480×272，内容区 464×210）：
  1、提示行：当前生效链路（由 net_drv 的 NET_ACTIVE_UPDATED 推送）
  2、四行网卡列表：序号 | 网卡名 | 实时状态 | 上移 / 下移
     - 列表顺序即优先级顺序（第一行为最高优先级）
     - 点击「上移 / 下移」立即调整顺序、保存并生效
     - 当前生效的那一行，状态列以「生效|状态」前缀 + 主题主色高亮
  3、底部按钮：恢复默认顺序

数据链路（顺序即优先级）：
  上移/下移 → net_config.save({ priority = ... }) → 发布 NET_CONFIG_UPDATED
            → net_drv.on_net_config_updated → exnetif.set_priority_order（增量重排网卡优先级）

数据来源（既有消息 + 本次新增消息）：
  STATUS_ETH_UPDATED(e1,ip1,e2,ip2)              以太网1 / 以太网2
  STATUS_WIFI_UPDATED(conn,ssid,level,rssi)      WiFi
  STATUS_SIGNAL_UPDATED(level)                   4G 信号
  NET_ACTIVE_UPDATED(net_type,adapter,name)      当前生效链路（net_drv 新增）
  NET_CONFIG_UPDATED(cfg)                        配置变更（含内置网页端改动的同步）
  NETWORK_STATUS_QUERY                           打开页面时主动查询

@note 本页与内置网页的 /api/priority 共用同一份 net_config.priority，两端配置天然同步。

@note 交互方式为「纯排序」（上移 / 下移），不做网卡启用 / 停用开关；四张网卡始终参与调度。
]]

local theme = require "ui_theme"
local net_config = require "net_config"

local win_id = nil
local main_container
local active_label                    -- 提示行的「当前生效」数值标签
local slots = {}                      -- 4 个槽位句柄：{ idx = label, name = label, status = label }
local cur_priority = {}               -- 界面当前顺序（槽位索引 → 网卡 key）

-- ==================== 常量 ====================

-- 四张网卡：key（net_config.priority 中的取值）→ 显示名
local NET_KEYS  = { "eth1", "eth2", "wifi", "4g" }
local NET_NAMES = { eth1 = "网口1", eth2 = "网口2", wifi = "WiFi", ["4g"] = "4G" }

-- 默认优先级顺序（与 net_config.DEFAULTS.priority 保持一致）
local DEFAULT_PRIORITY = { "wifi", "eth1", "eth2", "4g" }

-- 布局几何（内容区 464×210 = 提示行 32 + 4 + 4 行 ×32 + 3 ×4 + 4 + 按钮 30）
local HINT_H = 32     -- 提示行高
local ROW_H  = 32     -- 网卡行高
local GAP    = 4      -- 行间距 / 区块间距
local LH     = 19     -- 文字行盒高（16px 字体：字号 + 3）
local TY     = 6      -- 行内文字 Y（(32-19)/2）
local BH     = 26     -- 行内按钮高
local BY     = 3      -- 行内按钮 Y（(32-26)/2）
local BTN_W  = 140    -- 底部按钮宽
local BTN_H  = 30     -- 底部按钮高

-- ==================== 状态缓存 ====================

local cache = { eth1 = false, eth2 = false, wifi = false, ssid = "", mobile = 0 }
local active = "查询中"               -- 当前生效链路名

-- ==================== 数据加工 ====================

--[[
优先级数组规范化：过滤非法项、去重，并按 NET_KEYS 补齐缺失项

@local
@function normalize_priority
@param p table|nil net_config.priority
@return table 长度固定为 4、含四张网卡各一次的顺序表
]]
local function normalize_priority(p)
    local order, used = {}, {}
    if type(p) == "table" then
        for _, key in ipairs(p) do
            if NET_NAMES[key] and not used[key] then
                used[key] = true
                order[#order + 1] = key
            end
        end
    end
    for _, key in ipairs(NET_KEYS) do
        if not used[key] then
            used[key] = true
            order[#order + 1] = key
        end
    end
    return order
end

--[[
取某张网卡的显示状态文本与颜色

@local
@function status_text
@param key string 网卡 key
@return string 状态文本
@return number 语义色
]]
local function status_text(key)
    if key == "eth1" then
        return cache.eth1 and "已连接" or "未连接",
               cache.eth1 and theme.SEM.success or theme.SEM.danger
    elseif key == "eth2" then
        return cache.eth2 and "已连接" or "未连接",
               cache.eth2 and theme.SEM.success or theme.SEM.danger
    elseif key == "wifi" then
        if cache.wifi then
            local s = (cache.ssid ~= "") and cache.ssid or "已连接"
            if #s > 20 then s = string.sub(s, 1, 20) end
            return s, theme.SEM.success
        end
        return "未连接", theme.SEM.danger
    end
    -- 4G
    if cache.mobile and cache.mobile > 0 then
        return "信号" .. tostring(cache.mobile) .. "级", theme.SEM.success
    end
    return "无服务", theme.SEM.danger
end

--[[
按当前顺序与状态缓存重绘界面（序号 / 名称 / 状态 / 生效标记 / 提示行）

@local
@function render
]]
local function render()
    cur_priority = normalize_priority(net_config.load().priority)
    for i = 1, 4 do
        local s = slots[i]
        local key = cur_priority[i]
        if s and key then
            local name = NET_NAMES[key] or key
            local text, color = status_text(key)
            if active == name then
                text = "生效" .. theme.CHAR.sep .. text
                color = theme.C.primary
            end
            s.idx:set_text(tostring(i))
            s.name:set_text(name)
            s.status:set_text(text)
            s.status:set_color(color)
        end
    end
    if active_label then
        active_label:set_text(active or "查询中")
    end
end

-- ==================== 交互回调（命名函数 / 工厂函数，禁止裸匿名函数） ====================

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
上移 / 下移：交换相邻两项并把新顺序写入 net_config（保存即生效）

@local
@function do_move
@param slot_index number 槽位索引（1~4）
@param dir number -1 = 上移，1 = 下移
]]
local function do_move(slot_index, dir)
    local ni = slot_index + dir
    if ni < 1 or ni > #cur_priority then return end
    local p = {}
    for i = 1, #cur_priority do p[i] = cur_priority[i] end
    p[slot_index], p[ni] = p[ni], p[slot_index]
    -- 写入配置并广播：net_drv 收到 NET_CONFIG_UPDATED 后增量重排 exnetif 优先级
    net_config.save({ priority = p })
    render()
end

--[[
生成「上移 / 下移」点击回调（工厂函数：按值捕获槽位与方向，避免循环变量捕获问题）

@local
@function make_move_handler
@param slot_index number 槽位索引
@param dir number -1 = 上移，1 = 下移
@return function 点击回调
]]
local function make_move_handler(slot_index, dir)
    return function()
        do_move(slot_index, dir)
    end
end

--[[
恢复默认顺序

@local
@function on_reset_click
]]
local function on_reset_click()
    local p = {}
    for i = 1, #DEFAULT_PRIORITY do p[i] = DEFAULT_PRIORITY[i] end
    net_config.save({ priority = p })
    render()
end

-- ==================== 状态消息回调 ====================

--[[
以太网状态更新（网口1 / 网口2）

@local
@function on_eth_updated
@param e1 number 网口1 连接状态
@param ip1 string 网口1 IP
@param e2 number 网口2 连接状态
@param ip2 string 网口2 IP
]]
local function on_eth_updated(e1, ip1, e2, ip2)
    cache.eth1 = (e1 and e1 > 0) and true or false
    cache.eth2 = (e2 and e2 > 0) and true or false
    if exwin.is_active(win_id) then render() end
end

--[[
WiFi 状态更新

@local
@function on_wifi_updated
@param conn boolean 是否已连接
@param ssid string WiFi 名称
@param level number 信号等级
@param rssi number 信号强度
]]
local function on_wifi_updated(conn, ssid, level, rssi)
    cache.wifi = conn and true or false
    cache.ssid = ssid or ""
    if exwin.is_active(win_id) then render() end
end

--[[
4G 信号等级更新

@local
@function on_signal_updated
@param level number 信号等级(0~5)
]]
local function on_signal_updated(level)
    cache.mobile = level or 0
    if exwin.is_active(win_id) then render() end
end

--[[
当前生效链路更新（多网融合调度结果）

@local
@function on_active_updated
@param net_type string|nil 网卡类型字符串
@param adapter number 网卡编号
@param name string 中文网卡名
]]
local function on_active_updated(net_type, adapter, name)
    active = name or "查询中"
    if exwin.is_active(win_id) then render() end
end

--[[
网络配置变更（本页操作 / 内置网页端操作都会触发）

@local
@function on_net_config_updated
@param cfg table 新的网络配置
]]
local function on_net_config_updated(cfg)
    if exwin.is_active(win_id) then render() end
end

-- ==================== UI 构建 ====================

--[[
创建多网融合配置页 UI

@local
@function create_ui
]]
local function create_ui()
    local ctx = theme.page({ title = "多网融合", on_back = on_back_click })
    main_container = ctx.base

    -- 提示行：当前生效链路
    local y = ctx.y
    local _, act = theme.kv_row(ctx.base, {
        x = ctx.x, y = y, w = ctx.w, h = HINT_H,
        label = "当前生效", value = "查询中", value_color = theme.C.primary,
    })
    active_label = act
    y = y + HINT_H + GAP

    -- 四行网卡：序号 | 网卡名 | 实时状态 | 上移 | 下移
    slots = {}
    for i = 1, 4 do
        local row = theme.card(ctx.base, {
            x = ctx.x, y = y, w = ctx.w, h = ROW_H,
            color = theme.C.panel, radius = theme.R.sm, border = theme.C.stroke_soft,
        })
        local idx = theme.label(row, {
            x = 10, y = TY, w = 24, h = LH,
            text = tostring(i), color = theme.C.t3,
        })
        local name = theme.label(row, {
            x = 36, y = TY, w = 90, h = LH,
            text = "--", color = theme.C.t1,
        })
        local st = theme.label(row, {
            x = 132, y = TY, w = 190, h = LH,
            text = "--", color = theme.C.t2,
        })
        -- 行内按钮：x 自右向左布局（右边缘留 10px，两按钮间距 6px）
        theme.ghost(row, {
            x = ctx.w - 128, y = BY, w = 56, h = BH,
            text = "上移", size = "small", on_click = make_move_handler(i, -1),
        })
        theme.ghost(row, {
            x = ctx.w - 66, y = BY, w = 56, h = BH,
            text = "下移", size = "small", on_click = make_move_handler(i, 1),
        })
        slots[i] = { idx = idx, name = name, status = st }
        y = y + ROW_H + GAP
    end

    -- 底部按钮：恢复默认顺序
    theme.btn(ctx.base, {
        x = ctx.x + math.floor((ctx.w - BTN_W) / 2), y = y, w = BTN_W, h = BTN_H,
        text = "恢复默认顺序", on_click = on_reset_click,
    })
end

-- ==================== 窗口生命周期 ====================

--[[
窗口创建回调

@local
@function on_create
]]
local function on_create()
    log.info("multi_net_win", "[UI-MARK] 多网融合配置页 v1.0 已加载")
    create_ui()
    sys.subscribe("STATUS_ETH_UPDATED", on_eth_updated)
    sys.subscribe("STATUS_WIFI_UPDATED", on_wifi_updated)
    sys.subscribe("STATUS_SIGNAL_UPDATED", on_signal_updated)
    sys.subscribe("NET_ACTIVE_UPDATED", on_active_updated)
    sys.subscribe("NET_CONFIG_UPDATED", on_net_config_updated)
    -- 主动查询一次各网络状态与当前生效链路，避免打开页面时显示滞后
    sys.publish("NETWORK_STATUS_QUERY")
    render()
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
    active_label = nil
    slots = {}
    cur_priority = {}
    sys.unsubscribe("STATUS_ETH_UPDATED", on_eth_updated)
    sys.unsubscribe("STATUS_WIFI_UPDATED", on_wifi_updated)
    sys.unsubscribe("STATUS_SIGNAL_UPDATED", on_signal_updated)
    sys.unsubscribe("NET_ACTIVE_UPDATED", on_active_updated)
    sys.unsubscribe("NET_CONFIG_UPDATED", on_net_config_updated)
    win_id = nil
end

--[[
窗口获得焦点回调

@local
@function on_get_focus
]]
local function on_get_focus()
    sys.publish("NETWORK_STATUS_QUERY")
    if net_config then render() end
end

--[[
窗口失去焦点回调

@local
@function on_lose_focus
]]
local function on_lose_focus() end

--[[
OPEN_MULTINET_WIN 消息处理器（单实例保护）

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
        on_get_focus = on_get_focus,
        on_lose_focus = on_lose_focus,
    })
end

sys.subscribe("OPEN_MULTINET_WIN", open_handler)
