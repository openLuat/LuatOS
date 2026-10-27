--[[
@module  settings_channel_app
@summary UART3 口复用配置（4G / WiFi / GNSS / 蓝牙 四选一）
@version 1.0
@date    2026.10.26
@author  江访
@usage
本板 UART3 同时引到 4G / WiFi(6205) / GNSS(Air510W) / 蓝牙(Air5101S) 四个模组，
底板靠硬件选路，同一时刻只能有一路占用这条串口。本模块把「占哪一路」做成可持久化
的配置项（fskv key = uart3_mode），给 UI 与业务层提供同一份读写接口。

=== 四选的语义 ===

  4g   → 开机初始化 以太网 + 4G（UART3 按 2Mbps 给 4G），不加载 WiFi 业务层
  wifi → 开机初始化 以太网 + WiFi（UART3 按 2Mbps 给 6205），不加载 4G
  gnss → 开机不初始化 4G / WiFi（UART3 空着），GNSS 测试页独占 UART3
  ble  → 开机不初始化 4G / WiFi（UART3 空着），蓝牙测试页独占 UART3

=== 生效时机 ===

4G / WiFi 属于「开机建网卡」：airlink.init + exnetif 是一次性初始化，运行期重建网卡
会把 6205 / 4G 直接踢下线（见 net_manager 头部「Airlink WiFi 运行期切换凭证」注释）。
所以本配置一律「保存 → 重启生效」，不做热切换。GNSS / 蓝牙本来就是页面级抢占，
重启后进对应页面即可用。

=== 消息协议 ===

订阅: CHANNEL_GET           → 发布 CHANNEL_VALUE(mode)
订阅: CHANNEL_SET(mode)     → 发布 CHANNEL_SET_RESULT(ok, mode, err)
订阅: CHANNEL_REBOOT        → 立即重启（配置页的「立即重启」按钮）

=== 被谁使用 ===

  app_main.optional()   → apply_to_config() 收口 features.wifi / features.net_4g
  net_manager.init()    → 自己读同一个 key，过滤掉互斥的 network 条目
  settings_ble_app / settings_gnss_app → 打开前校验当前通道是不是自己
  ui/settings/settings_channel_win.lua → 配置页
]]

local M = {}

-- fskv 键名（net_manager 里也直接读这个键，改名必须两处同步）
M.KEY = "uart3_mode"

-- 合法取值与展示名（顺序即页面展示顺序）
M.MODES  = { "4g", "wifi", "gnss", "ble" }
M.LABELS = { ["4g"] = "4G", wifi = "WiFi", gnss = "GNSS", ble = "蓝牙" }

-- 每个模式的用途说明（页面副标题用）
M.DESC = {
    ["4g"] = "UART3 给 4G 模组，开机联网（以太网不通时回落）",
    wifi   = "UART3 给 WiFi(6205)，开机按已保存凭证连 AP",
    gnss   = "UART3 留给 GNSS 测试页，勿开 4G / WiFi",
    ble    = "UART3 留给蓝牙测试页，勿开 4G / WiFi",
}

--[[模式名 → 展示名：未知值原样返回，避免 UI 出现 nil]]
function M.label(mode)
    return M.LABELS[mode] or tostring(mode or "--")
end

function M.valid(mode)
    for _, m in ipairs(M.MODES) do
        if m == mode then return true end
    end
    return false
end

--[[从 config 推断缺省模式（fskv 里没有记录时的兜底）
规则按「配置里实际写了哪几个可用通道」判断，保证老配置升级后行为不变：
  network 里只有 4G  → 4g
  network 里只有 WiFi → wifi
  两条都在            → 4g（沿用本工程历史默认）
  都没有              → 看 features，再看 GNSS/蓝牙，最后落 gnss
]]
function M.default_mode(cfg)
    cfg = cfg or _G.project_config or {}
    local has_wifi, has_cell = false, false
    local nets = cfg.network
    if type(nets) == "table" then
        for _, net_cfg in ipairs(nets) do
            local t = net_cfg.type or ""
            if t:find("wifi", 1, true) then has_wifi = true end
            if t:find("4g", 1, true) then has_cell = true end
        end
    end
    if has_cell then return "4g" end
    if has_wifi then return "wifi" end

    local fe = cfg.features or {}
    if fe.net_4g then return "4g" end
    if fe.wifi then return "wifi" end
    if fe.ble then return "ble" end
    return "gnss"
end

--[[读当前通道模式：fskv 有合法值就用它，否则按 config 推断（不写回，保持只读）]]
function M.get(cfg)
    local ok, value = pcall(fskv.get, M.KEY)
    if ok and type(value) == "string" and M.valid(value) then
        return value
    end
    return M.default_mode(cfg)
end

--[[保存通道模式（重启后生效）
@return boolean, string|nil 是否保存成功 / 失败原因
]]
function M.set(mode)
    if not M.valid(mode) then
        return false, "非法通道: " .. tostring(mode)
    end
    local ok, err = pcall(fskv.set, M.KEY, mode)
    if not ok or err == false then
        return false, "fskv 写入失败: " .. tostring(err)
    end
    log.info("settings_channel", "通道已保存", mode, tostring(M.label(mode)), "重启后生效")
    return true
end

--[[把通道模式收口到 features.wifi / features.net_4g
必须在网络初始化和 UI 门控之前调用（app_main.optional 开头），这样
features 的判断结果、net_manager 的 network 过滤、设置页入口三者一致。

注意：只改这两个布尔量，不动 features 里的其它开关，也不改 config.network
（network 里两条无线条目都保留，由 net_manager 按模式剔除）。
]]
function M.apply_to_config(cfg)
    cfg = cfg or _G.project_config or {}
    local fe = cfg.features
    if type(fe) ~= "table" then return nil end

    local mode = M.get(cfg)
    fe.net_4g = (mode == "4g")
    fe.wifi   = (mode == "wifi")
    log.info("settings_channel", "UART3 通道", mode, tostring(M.label(mode)),
             "net_4g=" .. tostring(fe.net_4g), "wifi=" .. tostring(fe.wifi))
    return mode
end

-- ==================== 消息接口 ====================

sys.subscribe("CHANNEL_GET", function()
    sys.publish("CHANNEL_VALUE", M.get())
end)

sys.subscribe("CHANNEL_SET", function(mode)
    local ok, err = M.set(mode)
    sys.publish("CHANNEL_SET_RESULT", ok, mode, err)
end)

sys.subscribe("CHANNEL_REBOOT", function()
    log.info("settings_channel", "按用户请求重启，使通道配置生效")
    pcall(rtos.reboot)
end)

return M
