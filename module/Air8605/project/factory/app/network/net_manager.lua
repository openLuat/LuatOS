--[[
@module  net_manager
@summary 统一网络管理器：读取 project_config 驱动所有网络接口的初始化
@version 1.7
@date    2026.11.05
@author  江访
@usage
在 app_main.lua 中按如下顺序加载：
  require "net_manager"      → 注册所有接口（不初始化）
  require "net_init"         → 订阅 IP_READY/IP_LOSE 事件
  require "wifi_app_real"    → WiFi 业务层
  之后由 app_main.lua 主动调用 net_manager.init() 触发兜底网络初始化

===== 时序说明 =====
net_manager 在 platform_loader.lua 的编译清单中有 require（打包进固件用），
但实际运行时 _G.project_config 在 platform_loader 加载完成后才就绪。
因此 net_manager 采用两阶段设计：
  阶段1 (require)：注册所有接口函数，不读 config
  阶段2 (init)：由 app_main.lua 传入 config 后真正初始化

===== 新格式 config.network 示例 =====

    network = {
        -- 自带 WiFi（Air8101/Air8000 芯片内置）
        { type = "wifi_native" },

        -- Airlink SPI WiFi（Air1602 外挂模组）
        -- { type = "wifi_airlink_spi", spi_id = 1, cs_pin = 8, rdy_pin = 14 },

        -- Airlink UART WiFi（Air1601 6205 模组）
        -- { type = "wifi_airlink_uart", uart_id = 3, baud = 2000000 },

        -- SPI 以太网（CH390H/W5500）
        -- { type = "eth_spi", chip = "CH390", spi_id = 0, cs_pin = 34, irq_pin = 9 },

        -- 自带 4G
        -- { type = "4g_native" },

        -- Airlink SPI 4G（外挂 Air780EPM）
        -- { type = "4g_airlink_spi", spi_id = 0, cs_pin = 15, rdy_pin = 48 },

        -- Airlink UART 4G
        -- { type = "4g_airlink_uart", uart_id = 1, baud = 2000000 },
    }

===== 优先级顺序 =====
config.network 的声明顺序即优先级顺序，写在最前的网卡优先上网。
config.network 不存在时由旧字段自动构造，默认顺序：以太网 > WiFi > 4G。

===== 向后兼容 =====
config.network 不存在时，自动从 features.wifi / features.net_4g / features.ethernet 等旧字段
构造 network 列表，默认顺序 以太网 > WiFi > 4G。

===== 网络开关 =====
net_app_config.enabled[type] 控制每个网络是否参与组网，网络设置页是唯一真源。
airlink 网络开关需要重启生效（airlink 无独立 stop 接口），非 airlink 网络在线生效。
运行期只动链路层（断/拉 PHY、飞行模式、wlan.connect/disconnect），
不调用 exnetif.close，不重复调用 exnetif.set_priority_order。

===== 对外接口 =====

net_manager.init(config)                           → 传入 project_config，初始化所有兜底网络
net_manager.build_priority_in_order(wifi_entry)    → 按 config.network 声明顺序构建优先级
net_manager.build_initial_priority()               → 初始优先级（仅非WiFi的兜底网络）
net_manager.build_wifi_priority(ssid, pwd, bssid, adv)
                                                   → 包含目标WiFi的优先级
net_manager.build_no_wifi_priority()               → 仅兜底网络
net_manager.apply(priority)                        → 调用 exnetif.set_priority_order（每次开机一次）
net_manager.get_network_config(type)               → 按类型名匹配返回网络配置项
net_manager.get_wifi_hw_config(suffix)             → 返回 Airlink WiFi 硬件参数
net_manager.has_wifi()                             → 检查配置中是否包含 WiFi
net_manager.on_wifi_disabled()                     → WiFi 关闭时重建兜底网络
net_manager.list_networks()                        → 返回网络列表（含开关、状态、图标）
net_manager.list_types()                           → 返回 config.network 的网络类型名列表
net_manager.preview_toggle(id, enable)             → 预演开关结果（互斥、是否需重启）
net_manager.set_net_enabled(id, enable)            → 设置网络开关并在线生效
net_manager.has_active_network()                   → 是否存在已联网的网络
]]

local exnetif = require "exnetif"
local net_storage = require "net_storage"

local net_manager = {}

-- ==================== 内部状态（init 后方可用） ====================
local _initialized = false
local _config = nil          -- project_config 引用
local _chip = ""             -- 芯片型号
local _is_air8101 = false    -- 是否是 Air8101 系列
local _network_configs = {}  -- 网络配置列表
local _enabled = {}          -- 网络开关表 { [type] = boolean }
local _net_state = {}        -- 网络状态表 { [type] = "CONNECTED"|"CONNECTING"|"DISCONNECTED" }
local _pending_reboot = {}   -- 待重启生效的网络 { [type] = true }
local _active_adapter = nil  -- 当前活跃网卡编号
-- 每次开机只允许调用一次 exnetif.set_priority_order
local _priority_applied = false
-- 开机 airlink WiFi 已传递的凭证（用于 wifi_app_real 跳过冗余 apply_wifi）
local _boot_wifi_credential = nil  -- { ssid, password, bssid }

-- ==================== 一、向后兼容层 ====================
-- 从旧格式 features/ethernet/net_4g_config 自动构造 network[]
-- 仅在 config.network 不存在时启用

local function legacy_to_network()
    local nets = {}
    local features = _config.features or {}

    -- 1. SPI 以太网
    if features.ethernet then
        local eth = _config.ethernet or {}
        table.insert(nets, {
            type = "eth_spi",
            chip = eth.chip or "CH390",
            spi_id = eth.spi_id,
            cs_pin = eth.pin_cs,
            irq_pin = eth.pin_irq,
            pwr_pin = eth.pin_pwr,
        })
    end

    -- 2. WiFi
    if features.wifi then
        if _chip:find("Air1601") or _chip:find("Air1602")
            or _chip:find("Air1780") then
            -- Airlink SPI WiFi（Air1601/1602/Air1780 外挂模组）
            local w = _config.wifi or {}
            table.insert(nets, {
                type = "wifi_airlink_spi",
                spi_id = w.spi_id or 1,
                cs_pin = w.cs_pin or 8,
                rdy_pin = w.rdy_pin or 14,
                speed = w.speed or (20 * 1000000),
            })
        else
            -- 原生 WiFi（Air8101/Air8000/PC 等）
            table.insert(nets, { type = "wifi_native" })
        end
    end

    -- 3. 4G 网络
    if features.net_4g then
        local cfg_4g = _config.net_4g_config or {}
        if cfg_4g.type == "airlink" then
            if cfg_4g.airlink_uart_id then
                table.insert(nets, {
                    type = "4g_airlink_uart",
                    uart_id = cfg_4g.airlink_uart_id,
                    baud = cfg_4g.airlink_uart_baud or 2000000,
                    adapter = cfg_4g.airlink_adapter,
                })
            else
                table.insert(nets, {
                    type = "4g_airlink_spi",
                    spi_id = cfg_4g.airlink_spi_id,
                    cs_pin = cfg_4g.airlink_cs_pin,
                    rdy_pin = cfg_4g.airlink_rdy_pin,
                })
            end
        else
            table.insert(nets, { type = "4g_native" })
        end
    end

    return nets
end

-- ==================== 二、网络开关与链路层 ====================

local NET_INFO = {
    eth_spi           = { name = "以太网", group = "eth",  icon = "ethernet" },
    wifi_native       = { name = "WiFi",   group = "wifi", icon = "wifi" },
    wifi_airlink_spi  = { name = "WiFi",   group = "wifi", icon = "wifi" },
    wifi_airlink_uart = { name = "WiFi",   group = "wifi", icon = "wifi" },
    ["4g_native"]     = { name = "4G",     group = "4g",   icon = "4Gxinhao4" },
    ["4g_airlink_spi"]= { name = "4G",     group = "4g",   icon = "4Gxinhao4" },
    ["4g_airlink_uart"]={ name = "4G",     group = "4g",   icon = "4Gxinhao4" },
}

--[[
判断网络类型是否为 airlink 网络
@param string type_name 网络类型名
@return boolean
]]
local function is_airlink_type(type_name)
    return type(type_name) == "string"
        and type_name:find("_airlink_", 1, true) ~= nil
end

--[[
查询网络类型的基础信息
@param string type_name 网络类型名
@return table { name, group, icon }
]]
local function net_info(type_name)
    return NET_INFO[type_name] or { name = type_name or "", group = "other", icon = "" }
end

--[[
查询网络开关，无记录时默认开启
@param string type_name 网络类型名
@return boolean
]]
local function is_net_enabled(type_name)
    if type(type_name) ~= "string" or type_name == "" then return false end
    local enable = _enabled[type_name]
    if enable == nil then return true end
    return enable == true
end

--[[
按类型名查找网络配置项
@param string id 网络类型名
@return table or nil
]]
local function find_config(id)
    for _, net_cfg in ipairs(_network_configs or {}) do
        if net_cfg.type == id then return net_cfg end
    end
    return nil
end

--[[
查询网络类型对应的网卡适配器编号
@param table net_cfg 网络配置项
@return number or nil
]]
local function net_adapter(net_cfg)
    local t = (net_cfg and net_cfg.type) or ""
    if t == "eth_spi" then
        return _is_air8101 and socket.LWIP_USER1 or socket.LWIP_ETH
    end
    if t:find("wifi", 1, true) then return socket.LWIP_STA end
    if t == "4g_native" then return socket.LWIP_GP end
    return net_cfg.adapter or socket.LWIP_GP_GW
end

--[[
构建以太网驱动参数
@param table net_cfg 网络配置项
@return table or nil
]]
local function build_eth_param(net_cfg)
    if not net_cfg then return nil end
    local eth_opts = { spi = net_cfg.spi_id, cs = net_cfg.cs_pin }
    if net_cfg.irq_pin then eth_opts.irq = net_cfg.irq_pin end
    local eth_chip = netdrv.CH390  -- 默认 CH390，W5500 待芯片层注册
    local param = { tp = eth_chip, opts = eth_opts }
    if net_cfg.pwr_pin then param.pwrpin = net_cfg.pwr_pin end
    return param
end

-- 自动连接兜底账号：无已保存成功网络时使用
net_manager.DEFAULT_WIFI_SSID = "HJ"
net_manager.DEFAULT_WIFI_PASSWORD = "HJ@88888"

--[[
读取 WiFi 自动连接凭证
已保存列表里最近一次连接成功的网络优先，无则回落默认账号
@return string ssid, string password, string bssid, string source  source: "saved" / "default"
]]
function net_manager.pick_wifi_credential()
    local ok_saved, saved_list = pcall(fskv.get, "wifi_saved_list")
    if ok_saved and type(saved_list) == "table" then
        for _, entry in ipairs(saved_list) do
            if entry.last_connect_ok == true and entry.ssid and entry.ssid ~= "" then
                return entry.ssid, entry.password or "", entry.bssid, "saved"
            end
        end
    end
    return net_manager.DEFAULT_WIFI_SSID, net_manager.DEFAULT_WIFI_PASSWORD, nil, "default"
end

--[[
列出自动连接候选凭证（按推荐顺序）
首项与 pick_wifi_credential 一致，调用方按它比对开机凭证不会误判；
其余已保存网络按「连成功过 → 存过没验证 → 连失败过」分档排在后面，档内保持 saved_list 既有的顺序
末尾补默认账号并按 SSID 去重
@param number limit 可选，最多返回几项
@return table 数组，元素为 { ssid, password, bssid, source }，source: "saved" / "default"
]]
function net_manager.list_wifi_candidates(limit)
    local raw = {}
    local ssid, password, bssid, source = net_manager.pick_wifi_credential()
    raw[#raw + 1] = { ssid = ssid, password = password, bssid = bssid, source = source }

    local ok_saved, saved_list = pcall(fskv.get, "wifi_saved_list")
    if ok_saved and type(saved_list) == "table" then
        local buckets = { {}, {}, {} }
        for _, entry in ipairs(saved_list) do
            if entry.ssid and entry.ssid ~= "" then
                local b = 2
                if entry.last_connect_ok == true then
                    b = 1
                elseif entry.last_connect_ok == false then
                    b = 3
                end
                buckets[b][#buckets[b] + 1] = entry
            end
        end
        for i = 1, 3 do
            for _, entry in ipairs(buckets[i]) do
                raw[#raw + 1] = {
                    ssid = entry.ssid,
                    password = entry.password or "",
                    bssid = entry.bssid,
                    source = "saved",
                }
            end
        end
    end
    raw[#raw + 1] = {
        ssid = net_manager.DEFAULT_WIFI_SSID,
        password = net_manager.DEFAULT_WIFI_PASSWORD,
        bssid = nil,
        source = "default",
    }

    -- 按 SSID 去重，保住排在前面的那条
    local list, seen = {}, {}
    for _, cand in ipairs(raw) do
        if cand.ssid and cand.ssid ~= "" and not seen[cand.ssid] then
            seen[cand.ssid] = true
            list[#list + 1] = cand
        end
    end
    if type(limit) == "number" and limit > 0 then
        while #list > limit do table.remove(list) end
    end
    return list
end

--[[
打开或关闭以太网链路
@param table net_cfg 网络配置项
@param boolean enable 开关值
@return boolean
]]
local function eth_link_ctrl(net_cfg, enable)
    local param = build_eth_param(net_cfg)
    if not param then return false end
    local adapter = net_adapter(net_cfg)
    if enable then
        if param.pwrpin then
            gpio.setup(param.pwrpin, 1, gpio.PULLUP)
        end
        if param.tp ~= nil and param.opts and param.opts.spi then
            local result = spi.setup(param.opts.spi, nil, 0, 0, 8, 25600000)
            if result ~= 0 then
                log.error("net_manager", "以太网SPI打开失败:", result)
                return false
            end
        end
        if netdrv.CTRL_UPDOWN then
            netdrv.ctrl(adapter, netdrv.CTRL_UPDOWN, 1)
        end
    else
        if netdrv.CTRL_UPDOWN then
            netdrv.ctrl(adapter, netdrv.CTRL_UPDOWN, 0)
        end
        if param.opts and param.opts.spi then
            spi.close(param.opts.spi)
        end
        if param.pwrpin then
            gpio.set(param.pwrpin, 0)
            gpio.close(param.pwrpin)
        end
    end
    log.info("net_manager", "以太网链路:", net_cfg.type, enable and "打开" or "关闭")
    return true
end

--[[
打开或关闭原生 4G 链路
@param boolean enable 开关值
@return boolean
]]
local function g4_native_link_ctrl(enable)
    if not mobile or not mobile.flymode then
        log.error("net_manager", "当前固件不支持 mobile.flymode")
        return false
    end
    mobile.flymode(nil, enable == false)
    log.info("net_manager", "4G链路:", enable and "打开" or "关闭")
    return true
end

--[[
打开或关闭原生 WiFi 链路
@param boolean enable 开关值
@return boolean
]]
local function wifi_native_link_ctrl(enable)
    if not wlan or not wlan.connect or not wlan.disconnect then
        log.error("net_manager", "当前固件不支持 wlan 接口")
        return false
    end
    if not enable then
        wlan.disconnect()
        log.info("net_manager", "WiFi链路: 关闭")
        return true
    end
    local ssid, password, bssid = net_manager.pick_wifi_credential()
    if not ssid or ssid == "" then
        log.warn("net_manager", "无WiFi凭证，跳过连接")
        return false
    end
    return net_manager.reconnect_wifi(ssid, password, bssid)
end

--[[
打开或关闭单个网络的链路
@param string type_name 网络类型名
@param boolean enable 开关值
@return boolean
]]
local function link_ctrl(type_name, enable)
    local net_cfg = find_config(type_name)
    if not net_cfg then return false end
    local t = net_cfg.type
    if t == "eth_spi" then return eth_link_ctrl(net_cfg, enable) end
    if t == "4g_native" then return g4_native_link_ctrl(enable) end
    if t == "wifi_native" then return wifi_native_link_ctrl(enable) end
    log.warn("net_manager", "网络链路不支持在线切换:", t)
    return false
end

--[[
airlink 网络互斥防御，只保留 config.network 声明顺序中最靠前的一个
@return table or nil 需要落盘修正的开关表
]]
local function resolve_airlink_mutex()
    local fixes = nil
    local kept = nil
    for _, net_cfg in ipairs(_network_configs or {}) do
        local t = net_cfg.type
        if t and is_airlink_type(t) and is_net_enabled(t) then
            if kept then
                log.warn("net_manager", "airlink 互斥，关闭:", t, "保留:", kept)
                fixes = fixes or {}
                fixes[t] = false
                _enabled[t] = false
            else
                kept = t
            end
        end
    end
    return fixes
end

-- ==================== 三、初始化入口 ====================

--[[
初始化 net_manager（由 app_main.lua 在 config 就绪后调用）
@param config table  project_config
]]
function net_manager.init(config)
    if _initialized then return end

    _config = config or {}
    _chip = _config.chip or ""
    _is_air8101 = (_chip:find("Air8101") ~= nil)

    -- 读取 network 配置，旧格式则兼容转换
    _network_configs = _config.network or legacy_to_network()

    -- 网络开关：无记录的网络默认开启，airlink 互斥只保留优先级最高的一个
    -- _enabled 必须先填好再做互斥判断，否则 is_net_enabled 查空表一律按「已开启」处理，
    -- 互斥防御会把除 config.network 首个 airlink 之外的网络全部强制关闭并落盘
    net_storage.init()
    net_storage.load(_network_configs)
    _enabled = net_storage.get_all()
    local mutex_fix = resolve_airlink_mutex()
    if mutex_fix then
        net_storage.set_enabled_batch(mutex_fix)
        _enabled = net_storage.get_all()
    end

    log.info("net_manager", "初始化, 芯片:", _chip, "网络配置数:", #_network_configs)
    for _, net_cfg in ipairs(_network_configs) do
        log.info("net_manager", "  网络:", net_cfg.type)
    end

    -- 提前初始化 fskv，以便读取已保存 WiFi 列表
    -- wifi_storage 也会调 fskv.init()，重复调用是安全的
    pcall(fskv.init)

    -- 开机时初始化所有网络（以太网 + 4G + WiFi）
    -- WiFi 自动连接取最近一次连接成功的网络，无则回落默认账号
    -- airlink WiFi 关闭时只构建占位条目完成 6205 WLAN 硬件初始化（airlink.ready() 与扫描依赖它），不带凭证
    local wifi_cfg = net_manager.get_network_config("wifi")
    local wifi_entry = nil
    local wifi_ready = false
    local init_source = nil
    if wifi_cfg then
        wifi_ready = is_net_enabled(wifi_cfg.type)
    end
    if wifi_cfg and wifi_ready then
        local init_ssid = nil
        local init_password = nil
        local init_bssid = nil
        init_ssid, init_password, init_bssid, init_source = net_manager.pick_wifi_credential()
        log.info("net_manager", "开机使用WiFi:", init_ssid, "来源:", init_source)
        wifi_entry = net_manager.build_wifi_entry(init_ssid, init_password, init_bssid)
        -- 记录开机已传递的 WiFi 凭证，用于 wifi_app_real 判断是否需重复 apply_wifi
        _boot_wifi_credential = {
            ssid = init_ssid,
            password = init_password,
            bssid = init_bssid,
        }
    elseif wifi_cfg then
        log.info("net_manager", "WiFi 网络开关关闭，跳过 WiFi 初始化")
    end
    local priority = net_manager.build_priority_in_order(wifi_entry)
    if #priority > 0 then
        net_manager.apply(priority)
    end

    -- 发布 AIRLINK_WIFI_READY 信号，告知 wifi_app_real 硬件初始化已完成
    -- Native WiFi（如 Air8101/Air8000）的 get_wifi_hw_config() 返回 nil，不发布此信号
    if wifi_ready then
        sys.publish("AIRLINK_WIFI_READY")
    end

    _initialized = true
end

--[[
开机网络初始化是否完成
@return boolean 完成返回true
]]
function net_manager.is_boot_ready()
    return _initialized == true
end

-- ==================== 四、配置读取 ====================

--[[
按类型名前缀匹配，返回第一个匹配的网络配置项
@param pattern string  类型名模式，如 "wifi", "eth", "4g"
@return table or nil
]]
function net_manager.get_network_config(pattern)
    for _, net_cfg in ipairs(_network_configs) do
        if net_cfg.type and net_cfg.type:find(pattern, 1, true) then
            return net_cfg
        end
    end
    return nil
end

--[[
获取 Airlink WiFi 的硬件配置项（用于扫描初始化）
@param type_suffix string 可选过滤 "spi" 或 "uart"
@return table or nil
]]
function net_manager.get_wifi_hw_config(type_suffix)
    local pattern
    if type_suffix then
        pattern = "wifi_airlink_" .. type_suffix
    else
        pattern = "wifi_airlink"
    end
    for _, net_cfg in ipairs(_network_configs) do
        if net_cfg.type and net_cfg.type:find(pattern, 1, true) then
            return net_cfg
        end
    end
    return nil
end

--[[
查询 WiFi 网络开关是否开启
@return boolean 开启返回true
]]
function net_manager.is_wifi_enabled()
    local wifi_cfg = net_manager.get_network_config("wifi")
    if not wifi_cfg then return false end
    return is_net_enabled(wifi_cfg.type)
end

--[[
检查配置中是否包含 WiFi 类型
@return boolean
]]
function net_manager.has_wifi()
    if _config and _config.features and _config.features.wifi then
        return true
    end
    for _, net_cfg in ipairs(_network_configs) do
        if net_cfg.type and net_cfg.type:find("wifi", 1, true) then
            return true
        end
    end
    return false
end

-- ==================== 五、exnetif 条目构建 ====================

--[[
解析 airlink 通信模式：配置可写 airlink_mode 字符串，或直接写 airlink_type 常量，缺省用 default
]]
local function resolve_airlink_type(net_cfg, default)
    if not net_cfg then return default end
    if net_cfg.airlink_type ~= nil then return net_cfg.airlink_type end
    local name = net_cfg.airlink_mode
    if not name then return default end
    local const = ({
        spi_master  = "MODE_SPI_MASTER",
        hspi_master = "MODE_HSPI_MASTER",
        spi_slave   = "MODE_SPI_SLAVE",
        uart        = "MODE_UART",
    })[name]
    if not const then
        log.error("net_manager", "未知 airlink_mode:", name, "按缺省模式处理")
        return default
    end
    if (airlink ~= nil) and airlink[const] then return airlink[const] end
    log.error("net_manager", "固件不支持 airlink_mode:", name, const, "按缺省模式处理")
    return default
end

--[[
根据 type 和配置项构建单条 exnetif 优先级条目
]]
local function build_entry(net_cfg)
    if not net_cfg or not net_cfg.type then return nil end

    local t = net_cfg.type

    -- 原生 wifi（无 ssid 时不构建，由 wifi_app_real 带参数调用）
    if t == "wifi_native" then
        return nil
    end

    -- Airlink SPI WiFi（airlink_mode 决定通信模式，缺省 MODE_SPI_MASTER）
    if t == "wifi_airlink_spi" then
        return {
            airlink_wifi = {
                airlink_type = resolve_airlink_type(net_cfg, airlink.MODE_SPI_MASTER),
                airlink_spi_id = net_cfg.spi_id,
                airlink_cs_pin = net_cfg.cs_pin,
                airlink_rdy_pin = net_cfg.rdy_pin,
                airlink_spi_speed = net_cfg.speed or (20 * 1000000),
                auto_socket_switch = (net_cfg.auto_socket_switch == true),
            }
        }
    end

    -- Airlink UART WiFi
    if t == "wifi_airlink_uart" then
        return {
            airlink_wifi = {
                airlink_type = airlink.MODE_UART,
                airlink_uart_id = net_cfg.uart_id,
                airlink_uart_baud = net_cfg.baud or 2000000,
                auto_socket_switch = (net_cfg.auto_socket_switch == true),
            }
        }
    end

    -- SPI 以太网
    if t == "eth_spi" then
        local param = build_eth_param(net_cfg)
        if _is_air8101 then
            return { ETHUSER1 = param }
        else
            return { ETHERNET = param }
        end
    end

    -- 原生 4G
    if t == "4g_native" then
        return { LWIP_GP = true }
    end

    -- Airlink SPI 4G
    if t == "4g_airlink_spi" then
        local acfg = {
            airlink_type = resolve_airlink_type(net_cfg, airlink.MODE_SPI_MASTER),
            auto_socket_switch = (net_cfg.auto_socket_switch == true),
        }
        if net_cfg.spi_id then acfg.airlink_spi_id = net_cfg.spi_id end
        if net_cfg.cs_pin then acfg.airlink_cs_pin = net_cfg.cs_pin end
        if net_cfg.rdy_pin then acfg.airlink_rdy_pin = net_cfg.rdy_pin end
        return { airlink_4G = acfg }
    end

    -- Airlink UART 4G
    if t == "4g_airlink_uart" then
        local acfg = {
            airlink_type = airlink.MODE_UART,
            auto_socket_switch = (net_cfg.auto_socket_switch == true),
        }
        if net_cfg.uart_id then acfg.airlink_uart_id = net_cfg.uart_id end
        if net_cfg.baud then acfg.airlink_uart_baud = net_cfg.baud end
        if net_cfg.adapter then acfg.airlink_adapter = net_cfg.adapter end
        return { airlink_4G = acfg }
    end

    log.warn("net_manager", "未知网络类型:", t)
    return nil
end

--[[
构建单条 WiFi 条目（带 ssid/password，或仅用于硬件初始化的空 WiFi 条目）
由 wifi_app_real 在连接/扫描时调用
@param ssid string  可选，SSID；airlink 为空时构建占位条目初始化 WLAN 硬件，原生 WiFi 为空时返回 nil
@param password string  可选
@param bssid string  可选
@param adv_cfg table  可选，高级配置
@return table or nil
]]
function net_manager.build_wifi_entry(ssid, password, bssid, adv_cfg)
    local airlink_cfg = net_manager.get_wifi_hw_config()

    if airlink_cfg then
        local atype = resolve_airlink_type(airlink_cfg,
            (airlink_cfg.type == "wifi_airlink_uart") and airlink.MODE_UART or airlink.MODE_SPI_MASTER)

        local entry = {
            airlink_wifi = {
                airlink_type = atype,
                auto_socket_switch = (adv_cfg and adv_cfg.auto_socket_switch) == true,
            }
        }
        -- Airlink WiFi 占位：无 SSID 时用默认 SSID 初始化 6205 WLAN 状态。
        -- 和 demo 一样，connect 本身正确发送 0x201，连接失败不影响后续 scan。
        if not ssid or ssid == "" then
            entry.airlink_wifi.ssid = "luatos"
            entry.airlink_wifi.password = ""
        else
            entry.airlink_wifi.ssid = ssid
            entry.airlink_wifi.password = password
        end
        if bssid and bssid ~= "" then
            entry.airlink_wifi.bssid = bssid
        end
        if adv_cfg then
            if adv_cfg.need_ping ~= nil then entry.airlink_wifi.need_ping = adv_cfg.need_ping end
            if adv_cfg.local_network_mode ~= nil then entry.airlink_wifi.local_network_mode = adv_cfg.local_network_mode end
            if adv_cfg.ping_ip then entry.airlink_wifi.ping_ip = adv_cfg.ping_ip end
            if adv_cfg.ping_time then entry.airlink_wifi.ping_time = tonumber(adv_cfg.ping_time) end
        end
        if airlink_cfg.type == "wifi_airlink_spi" then
            if airlink_cfg.spi_id then entry.airlink_wifi.airlink_spi_id = airlink_cfg.spi_id end
            if airlink_cfg.cs_pin then entry.airlink_wifi.airlink_cs_pin = airlink_cfg.cs_pin end
            if airlink_cfg.rdy_pin then entry.airlink_wifi.airlink_rdy_pin = airlink_cfg.rdy_pin end
            if airlink_cfg.speed then entry.airlink_wifi.airlink_spi_speed = airlink_cfg.speed end
        else
            if airlink_cfg.uart_id then entry.airlink_wifi.airlink_uart_id = airlink_cfg.uart_id end
            if airlink_cfg.baud then entry.airlink_wifi.airlink_uart_baud = airlink_cfg.baud end
        end
        return entry
    end

    -- 原生 WiFi：无 SSID 时不构建条目，由 wifi_app_real 带参数调用
    if not ssid or ssid == "" then
        return nil
    end

    local entry = {
        WIFI = {
            ssid = ssid,
            password = password,
            bssid = bssid,
            auto_socket_switch = (adv_cfg and adv_cfg.auto_socket_switch) == true,
        }
    }
    if adv_cfg then
        if adv_cfg.need_ping ~= nil then entry.WIFI.need_ping = adv_cfg.need_ping end
        if adv_cfg.local_network_mode ~= nil then entry.WIFI.local_network_mode = adv_cfg.local_network_mode end
        if adv_cfg.ping_ip then entry.WIFI.ping_ip = adv_cfg.ping_ip end
        if adv_cfg.ping_time then entry.WIFI.ping_time = tonumber(adv_cfg.ping_time) end
    end
    return entry
end

-- ==================== 六、优先级列表构建 ====================

--[[
按 config.network 声明顺序构建优先级列表
WiFi 条目落在其声明位置，声明顺序即优先级顺序
@param wifi_entry table or nil  目标 WiFi 条目；nil 时不放 WiFi，仅兜底网络
@return table
]]
function net_manager.build_priority_in_order(wifi_entry)
    local priority = {}
    for _, net_cfg in ipairs(_network_configs or {}) do
        local t = net_cfg.type or ""
        if is_net_enabled(t) then
            if t:find("wifi", 1, true) then
                if wifi_entry then table.insert(priority, wifi_entry) end
            else
                local entry = build_entry(net_cfg)
                if entry then table.insert(priority, entry) end
            end
        end
    end
    return priority
end

--[[
构建初始优先级列表：只包含非 WiFi 的兜底网络（以太网 + 4G）
]]
function net_manager.build_initial_priority()
    return net_manager.build_priority_in_order(nil)
end

--[[
构建仅兜底网络优先级（WiFi 关闭/断开时使用）
]]
function net_manager.build_no_wifi_priority()
    return net_manager.build_initial_priority()
end

--[[
构建包含目标 WiFi 的完整优先级列表
按 config.network 声明顺序摆位，WiFi 条目落在其声明位置
exnetif 按数组顺序依次尝试，第一个获得 IP_READY 的成为活跃网卡
ssid 为空时也构建 WiFi 条目：仅用于硬件初始化，使 exnetif 管理 airlink 硬件，
这样 wlan.scan() 才能正常工作
]]
function net_manager.build_wifi_priority(ssid, password, bssid, adv_cfg)
    return net_manager.build_priority_in_order(
        net_manager.build_wifi_entry(ssid, password, bssid, adv_cfg))
end

--[[
exnetif 的 airlink 条目只带 SPI_ID / CS / RDY / SPEED，INT 中断脚不在其映射范围内，
由本模块在 set_priority_order 之前用 airlink.config(CONF_SPI_IRQ, pin) 配好
]]
local function apply_airlink_extra_config()
    if (airlink == nil) or (type(airlink.config) ~= "function") then return end
    for _, net_cfg in ipairs(_network_configs or {}) do
        if net_cfg.irq_pin and net_cfg.type and net_cfg.type:find("airlink", 1, true) then
            if airlink.CONF_SPI_IRQ then
                pcall(airlink.config, airlink.CONF_SPI_IRQ, net_cfg.irq_pin)
                log.info("net_manager", "airlink CONF_SPI_IRQ =", net_cfg.irq_pin)
            end
        end
    end
end

--[[
调用 exnetif.set_priority_order
@return boolean
]]
function net_manager.apply(priority)
    if _priority_applied then
        log.error("net_manager", "set_priority_order 每次开机只允许调用一次，已忽略")
        return false
    end
    if not priority or #priority == 0 then
        log.info("net_manager", "无可用网络，跳过 exnetif 初始化")
        return true
    end
    apply_airlink_extra_config()
    _priority_applied = true
    return exnetif.set_priority_order(priority)
end

--[[
连接 WiFi 热点（协程中执行）
@param string ssid WiFi SSID
@param string password WiFi密码
@param string or nil bssid_bin 二进制BSSID
]]
local function run_wifi_connect(ssid, password, bssid_bin)
    wlan.disconnect()
    sys.wait(500)
    wlan.connect(ssid, password, 1, bssid_bin)
    log.info("net_manager", "WiFi连接:", ssid)
end

--[[
运行阶段切换 WiFi 热点，只动链路层不重建优先级表
@param string ssid WiFi SSID
@param string password WiFi密码
@param string bssid 可选BSSID
@return boolean
]]
function net_manager.reconnect_wifi(ssid, password, bssid)
    if not ssid or ssid == "" then
        log.error("net_manager", "SSID不能为空")
        return false
    end
    if not wlan or not wlan.connect or not wlan.disconnect then
        log.error("net_manager", "当前固件不支持 wlan 接口")
        return false
    end
    local bssid_bin = nil
    if bssid and #bssid >= 12 then
        bssid_bin = string.fromHex(bssid)
    end
    sys.taskInit(run_wifi_connect, ssid, password, bssid_bin)
    return true
end

--[[
断开 WiFi 连接，不动网络开关
@return boolean
]]
function net_manager.disconnect_wifi()
    if not wlan or not wlan.disconnect then
        log.error("net_manager", "当前固件不支持 wlan 接口")
        return false
    end
    wlan.disconnect()
    log.info("net_manager", "WiFi断开连接")
    return true
end

--[[
导航新WiFi：开机阶段构建"兜底网络 + 目标WiFi"优先级列表并应用
运行阶段改为切换 WiFi 热点，不再重建优先级表
WiFi 条目按 config.network 声明位置摆位，不固定插到首位
@param ssid string  WiFi SSID
@param password string  WiFi密码
@param bssid string  可选BSSID
@param adv_cfg table  可选高级配置
@return boolean
]]
function net_manager.apply_wifi(ssid, password, bssid, adv_cfg)
    if _priority_applied then
        return net_manager.reconnect_wifi(ssid, password, bssid)
    end
    return net_manager.apply(
        net_manager.build_priority_in_order(
            net_manager.build_wifi_entry(ssid, password, bssid, adv_cfg)))
end

--[[
WiFi 关闭/断开时断开 WiFi 链路
由 wifi_app_real 在 WIFI_ENABLE_REQ(false) 或 WIFI_DISCONNECT_REQ 时调用
]]
function net_manager.on_wifi_disabled()
    return net_manager.disconnect_wifi()
end

--[[
获取开机时已传递给 airlink WiFi 的凭证（仅 airlink 平台有效）
用于 wifi_app_real 判断是否需要重复 apply_wifi
@return table or nil  { ssid, password, bssid }
]]
function net_manager.get_boot_wifi_credential()
    return _boot_wifi_credential
end

--[[
判断给定凭证是否与开机已传凭证相同（SSID + BSSID 双重匹配）
@param ssid string
@param bssid string or nil
@return boolean true=相同，skip apply_wifi
]]
function net_manager.is_same_as_boot_credential(ssid, bssid)
    if not _boot_wifi_credential then return false end
    -- SSID 必须相同
    if _boot_wifi_credential.ssid ~= ssid then return false end
    -- BSSID 有一方为空时跳过 BSSID 检查（只做 SSID 匹配）
    if not bssid or bssid == "" or not _boot_wifi_credential.bssid or _boot_wifi_credential.bssid == "" then
        return true
    end
    -- BSSID 都非空时做精确匹配
    return _boot_wifi_credential.bssid == bssid
end

-- ==================== 七、网络开关查询与切换 ====================

--[[
查询网络状态字符串
@param string type_name 网络类型名
@return string OFF / PENDING_REBOOT / CONNECTED / CONNECTING / DISCONNECTED
]]
local function net_status_of(type_name)
    if not is_net_enabled(type_name) then return "OFF" end
    if _pending_reboot[type_name] then return "PENDING_REBOOT" end
    return _net_state[type_name] or "DISCONNECTED"
end

--[[
查询网络的描述文本
@param table net_cfg 网络配置项
@return string
]]
local function net_detail(net_cfg)
    local t = net_cfg.type or ""
    if t == "eth_spi" then return "SPI 以太网 " .. (net_cfg.chip or "CH390") end
    if t == "wifi_native" then return "芯片内置 WiFi" end
    if t == "4g_native" then return "芯片内置 4G" end
    if t:find("_airlink_uart", 1, true) then return "Airlink UART 模组" end
    if t:find("_airlink_spi", 1, true) then return "Airlink SPI 模组" end
    return ""
end

--[[
返回 config.network 的网络类型名列表
@return table 类型名数组，按声明顺序
]]
function net_manager.list_types()
    local types = {}
    for _, net_cfg in ipairs(_network_configs or {}) do
        if net_cfg.type then types[#types + 1] = net_cfg.type end
    end
    return types
end

--[[
返回网络列表，含开关、状态与图标
@return table 数组，元素为
        { id, name, group, icon, is_airlink, enabled, status, detail }
]]
function net_manager.list_networks()
    local list = {}
    for _, net_cfg in ipairs(_network_configs or {}) do
        local t = net_cfg.type
        if t then
            local info = net_info(t)
            list[#list + 1] = {
                id = t,
                name = info.name,
                group = info.group,
                icon = info.icon,
                is_airlink = is_airlink_type(t),
                enabled = is_net_enabled(t),
                status = net_status_of(t),
                detail = net_detail(net_cfg),
            }
        end
    end
    return list
end

--[[
预演网络开关结果
@param string id 网络类型名
@param boolean enable 开关值
@return table { ok, need_reboot, will_disable, changes, reason }
]]
function net_manager.preview_toggle(id, enable)
    local result = {
        ok = false, need_reboot = false,
        will_disable = {}, changes = {}, reason = "",
    }
    if not find_config(id) then
        log.error("net_manager", "未知网络类型:", tostring(id))
        return result
    end
    local value = (enable == true)
    result.ok = true
    result.changes[id] = value

    if is_airlink_type(id) then
        result.need_reboot = true
        if value then
            for _, net_cfg in ipairs(_network_configs or {}) do
                local other = net_cfg.type
                if other and other ~= id and is_airlink_type(other)
                    and is_net_enabled(other) then
                    result.changes[other] = false
                    result.will_disable[#result.will_disable + 1] = other
                end
            end
            result.reason = (#result.will_disable > 0) and "airlink_mutex" or "airlink_switch"
        else
            result.reason = "airlink_switch"
        end
    end
    return result
end

--[[
设置网络开关
airlink 网络写入开关后需重启生效，非 airlink 网络立即切换链路
@param string id 网络类型名
@param boolean enable 开关值
@return boolean ok 开关是否已写入
@return boolean need_reboot 是否需要重启生效
]]
function net_manager.set_net_enabled(id, enable)
    local preview = net_manager.preview_toggle(id, enable)
    if not preview.ok then return false, false end

    -- _enabled 先同步再落盘：net_storage 落盘后同步发布 NET_CONFIG_CHANGED，
    -- 桌面图标显隐等订阅者当场执行，读到的必须是新开关
    for type_name, value in pairs(preview.changes) do
        _enabled[type_name] = (value == true)
    end
    net_storage.set_enabled_batch(preview.changes)
    _enabled = net_storage.get_all()

    if preview.need_reboot then
        for type_name in pairs(preview.changes) do
            _pending_reboot[type_name] = true
        end
        log.info("net_manager", "网络开关需重启生效:", id)
        sys.publish("NET_STATUS_CHANGED")
        return true, true
    end

    for type_name, value in pairs(preview.changes) do
        link_ctrl(type_name, value)
    end
    if exnetif.check_network_status then
        exnetif.check_network_status()
    end
    sys.publish("NET_STATUS_CHANGED")
    return true, false
end

--[[
是否存在已联网的网络
@return boolean
]]
function net_manager.has_active_network()
    if _active_adapter then return true end
    for _, net_cfg in ipairs(_network_configs or {}) do
        local t = net_cfg.type
        if t and is_net_enabled(t) and _net_state[t] == "CONNECTED" then
            return true
        end
    end
    return false
end

--[[
IP_READY 事件：网卡获得IP地址
@param string ip IP地址
@param number adapter 网卡编号
]]
local function on_ip_ready(ip, adapter)
    if not adapter then return end
    for _, net_cfg in ipairs(_network_configs or {}) do
        if net_cfg.type and net_adapter(net_cfg) == adapter then
            _net_state[net_cfg.type] = "CONNECTED"
        end
    end
    _active_adapter = adapter
    sys.publish("NET_STATUS_CHANGED")
end

--[[
IP_LOSE 事件：网卡丢失IP地址
@param number adapter 网卡编号
]]
local function on_ip_lose(adapter)
    if not adapter then return end
    for _, net_cfg in ipairs(_network_configs or {}) do
        if net_cfg.type and net_adapter(net_cfg) == adapter then
            _net_state[net_cfg.type] = "DISCONNECTED"
        end
    end
    if _active_adapter == adapter then _active_adapter = nil end
    sys.publish("NET_STATUS_CHANGED")
end

--[[
EXLIB_NETDRV_NETWORK_STATUS 事件：当前活跃网卡变化
@param string or nil net_type 当前网络类型，nil 表示全部断开
@param number net_adapter 当前网卡编号
]]
local function on_network_status(net_type, net_adapter)
    _active_adapter = net_type and net_adapter or nil
    sys.publish("NET_STATUS_CHANGED")
end

sys.subscribe("IP_READY", on_ip_ready)
sys.subscribe("IP_LOSE", on_ip_lose)
sys.subscribe("EXLIB_NETDRV_NETWORK_STATUS", on_network_status)

-- require 时不做任何初始化（config 还未就绪）
-- 由 app_main.lua 在 config 加载完成后调用 net_manager.init()

return net_manager
