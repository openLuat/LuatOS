--[[
@module  net_manager
@summary 统一网络管理器：读取 project_config 驱动所有网络接口的初始化
@version 1.1
@date    2026.06.26
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

===== 向后兼容 =====
config.network 不存在时，自动从 features.wifi / features.net_4g / features.ethernet 等旧字段
构造 network 列表。

===== 对外接口 =====

net_manager.init(config)                           → 传入 project_config，初始化所有兜底网络
net_manager.build_initial_priority()               → 初始优先级（仅非WiFi的兜底网络）
net_manager.build_wifi_priority(ssid, pwd, bssid, adv)
                                                   → 包含目标WiFi的优先级
net_manager.build_no_wifi_priority()               → 仅兜底网络
net_manager.apply(priority)                        → 调用 exnetif.set_priority_order
net_manager.get_network_config(type)               → 按类型名匹配返回网络配置项
net_manager.get_wifi_hw_config(suffix)             → 返回 Airlink WiFi 硬件参数
net_manager.has_wifi()                             → 检查配置中是否包含 WiFi
net_manager.on_wifi_disabled()                     → WiFi 关闭时重建兜底网络
]]

local exnetif = require "exnetif"

local net_manager = {}

-- ==================== 内部状态（init 后方可用） ====================
local _initialized = false
local _config = nil          -- project_config 引用
local _chip = ""             -- 芯片型号
local _is_air8101 = false    -- 是否是 Air8101 系列
local _network_configs = {}  -- 网络配置列表
-- 开机 airlink WiFi 已传递的凭证（用于 wifi_app_real 跳过冗余 update_wifi）
local _boot_wifi_credential = nil  -- { ssid, password, bssid }

-- ==================== 一、向后兼容层 ====================
-- 从旧格式 features/ethernet/net_4g_config 自动构造 network[]
-- 仅在 config.network 不存在时启用

local function legacy_to_network()
    local nets = {}
    local features = _config.features or {}

    -- 1. WiFi
    if features.wifi then
        if _chip:find("Air1601") or _chip:find("Air1602") then
            -- Airlink SPI WiFi（Air1601/1602 外挂模组）
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

    -- 2. SPI 以太网
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

-- ==================== 二、初始化入口 ====================

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

    log.info("net_manager", "初始化, 芯片:", _chip, "网络配置数:", #_network_configs)
    for _, net_cfg in ipairs(_network_configs) do
        log.info("net_manager", "  网络:", net_cfg.type)
    end

    -- 提前初始化 fskv，以便读取已保存 WiFi 列表
    -- wifi_storage 也会调 fskv.init()，重复调用是安全的
    pcall(fskv.init)

    -- 开机时初始化所有网络（以太网 + 4G + airlink WiFi 硬件）
    -- airlink WiFi 用占位 SSID 完成 6205 WLAN 初始化，后续扫描/连接无需再 init
    local priority = net_manager.build_initial_priority()
    local airlink_cfg = net_manager.get_wifi_hw_config()
    if airlink_cfg then
        -- 开机初始化 airlink WiFi 前，从 fskv 读取已保存 WiFi
        -- 有则优先使用已保存的第一个 WiFi，避免用固定 "luatos" 占位后再切换连接
        local init_ssid = "luatos"
        local init_password = ""
        local init_bssid = nil
        local ok_saved, saved_list = pcall(fskv.get, "wifi_saved_list")
        if ok_saved and type(saved_list) == "table" and #saved_list > 0
            and saved_list[1].ssid and saved_list[1].ssid ~= "" then
            local saved = saved_list[1]
            init_ssid = saved.ssid
            init_password = saved.password or ""
            init_bssid = saved.bssid
            log.info("net_manager", "开机使用已保存WiFi:", init_ssid)
        end
        if init_ssid == "luatos" then
            log.info("net_manager", "无已保存WiFi，使用默认占位: luatos")
        end
        local atype = (airlink_cfg.type == "wifi_airlink_uart")
            and airlink.MODE_UART
            or airlink.MODE_SPI_MASTER
        local entry = {
            airlink_wifi = {
                airlink_type = atype,
                ssid = init_ssid,
                password = init_password,
                auto_socket_switch = false,
            }
        }
        if init_bssid and init_bssid ~= "" then
            entry.airlink_wifi.bssid = init_bssid
        end
        if atype == airlink.MODE_SPI_MASTER then
            if airlink_cfg.spi_id then entry.airlink_wifi.airlink_spi_id = airlink_cfg.spi_id end
            if airlink_cfg.cs_pin then entry.airlink_wifi.airlink_cs_pin = airlink_cfg.cs_pin end
            if airlink_cfg.rdy_pin then entry.airlink_wifi.airlink_rdy_pin = airlink_cfg.rdy_pin end
        else
            if airlink_cfg.uart_id then entry.airlink_wifi.airlink_uart_id = airlink_cfg.uart_id end
            if airlink_cfg.baud then entry.airlink_wifi.airlink_uart_baud = airlink_cfg.baud end
        end
        table.insert(priority, 1, entry)
        -- 记录开机已传递的 WiFi 凭证，用于 wifi_app_real 判断是否需重复 update_wifi
        _boot_wifi_credential = {
            ssid = init_ssid,
            password = init_password,
            bssid = init_bssid,
        }
    end
    if #priority > 0 then
        net_manager.apply(priority)
    end

    -- 发布 AIRLINK_WIFI_READY 信号，告知 wifi_app_real 硬件初始化已完成
    -- Native WiFi（如 Air8101/Air8000）的 get_wifi_hw_config() 返回 nil，不发布此信号
    if airlink_cfg then
        sys.publish("AIRLINK_WIFI_READY")
    end

    _initialized = true
end

-- ==================== 三、配置读取 ====================

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

-- ==================== 四、exnetif 条目构建 ====================

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

    -- Airlink SPI WiFi
    if t == "wifi_airlink_spi" then
        return {
            airlink_wifi = {
                airlink_type = airlink.MODE_SPI_MASTER,
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
        local eth_opts = { spi = net_cfg.spi_id, cs = net_cfg.cs_pin }
        if net_cfg.irq_pin then eth_opts.irq = net_cfg.irq_pin end
        local chip_name = (net_cfg.chip or "CH390"):upper()
        local eth_chip = netdrv.CH390  -- 默认 CH390，W5500 待芯片层注册
        local param = { tp = eth_chip, opts = eth_opts }
        if net_cfg.pwr_pin then param.pwrpin = net_cfg.pwr_pin end
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
            airlink_type = airlink.MODE_SPI_MASTER,
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
@param ssid string  可选，SSID；为空时仅构建硬件初始化条目（用于扫描）
@param password string  可选
@param bssid string  可选
@param adv_cfg table  可选，高级配置
@return table or nil
]]
local function build_wifi_entry(ssid, password, bssid, adv_cfg)
    local airlink_cfg = net_manager.get_wifi_hw_config()

    if airlink_cfg then
        local atype = (airlink_cfg.type == "wifi_airlink_uart")
            and airlink.MODE_UART
            or airlink.MODE_SPI_MASTER

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
        if atype == airlink.MODE_SPI_MASTER then
            if airlink_cfg.spi_id then entry.airlink_wifi.airlink_spi_id = airlink_cfg.spi_id end
            if airlink_cfg.cs_pin then entry.airlink_wifi.airlink_cs_pin = airlink_cfg.cs_pin end
            if airlink_cfg.rdy_pin then entry.airlink_wifi.airlink_rdy_pin = airlink_cfg.rdy_pin end
        else
            if airlink_cfg.uart_id then entry.airlink_wifi.airlink_uart_id = airlink_cfg.uart_id end
            if airlink_cfg.baud then entry.airlink_wifi.airlink_uart_baud = airlink_cfg.baud end
        end
        return entry
    end

    -- 原生 WiFi
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

-- ==================== 五、优先级列表构建 ====================

--[[
构建初始优先级列表：只包含非 WiFi 的兜底网络（以太网 + 4G）
]]
function net_manager.build_initial_priority()
    local priority = {}
    for _, net_cfg in ipairs(_network_configs) do
        if not net_cfg.type or not net_cfg.type:find("wifi", 1, true) then
            local entry = build_entry(net_cfg)
            if entry then table.insert(priority, entry) end
        end
    end
    return priority
end

--[[
构建仅兜底网络优先级（WiFi 关闭/断开时使用）
]]
function net_manager.build_no_wifi_priority()
    return net_manager.build_initial_priority()
end

--[[
构建包含目标 WiFi 的完整优先级列表
优先级顺序：以太网 > WiFi > 4G
exnetif 按数组顺序依次尝试，第一个获得 IP_READY 的成为活跃网卡
]]
function net_manager.build_wifi_priority(ssid, password, bssid, adv_cfg)
    local priority = {}

    -- 以太网优先插入（第一优先级）
    for _, net_cfg in ipairs(_network_configs) do
        if net_cfg.type and net_cfg.type:find("eth", 1, true) then
            local entry = build_entry(net_cfg)
            if entry then table.insert(priority, entry) end
        end
    end

    -- WiFi（第二优先级）
    -- ssid 为空时也构建 WiFi 条目：仅用于硬件初始化，使 exnetif 管理 airlink 硬件，
    -- 这样 wlan.scan() 才能正常工作。无 SSID 时不会发起连接。
    local wifi_entry = build_wifi_entry(ssid, password, bssid, adv_cfg)
    if wifi_entry then table.insert(priority, wifi_entry) end

    -- 4G 第三优先级
    for _, net_cfg in ipairs(_network_configs) do
        if net_cfg.type and net_cfg.type:find("4g", 1, true) then
            local entry = build_entry(net_cfg)
            if entry then table.insert(priority, entry) end
        end
    end

    return priority
end

--[[
调用 exnetif.set_priority_order
@return boolean
]]
function net_manager.apply(priority)
    if not priority or #priority == 0 then
        log.info("net_manager", "无可用网络，跳过 exnetif 初始化")
        return true
    end
    return exnetif.set_priority_order(priority)
end

--[[
WiFi 关闭/断开时重建不含 WiFi 的兜底网络
由 wifi_app_real 在 WIFI_ENABLE_REQ(false) 或 WIFI_DISCONNECT_REQ 时调用
]]
function net_manager.on_wifi_disabled()
    net_manager.apply(net_manager.build_no_wifi_priority())
end

--[[
获取开机时已传递给 airlink WiFi 的凭证（仅 airlink 平台有效）
用于 wifi_app_real 判断是否需要重复 update_wifi
@return table or nil  { ssid, password, bssid }
]]
function net_manager.get_boot_wifi_credential()
    return _boot_wifi_credential
end

--[[
判断给定凭证是否与开机已传凭证相同（SSID + BSSID 双重匹配）
@param ssid string
@param bssid string or nil
@return boolean true=相同，skip update_wifi
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

-- require 时不做任何初始化（config 还未就绪）
-- 由 app_main.lua 在 config 加载完成后调用 net_manager.init()

return net_manager
