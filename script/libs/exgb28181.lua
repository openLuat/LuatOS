--[[
@module exgb28181
@summary GB28181(GB/T 28181-2016)设备侧协议库，简化国标视频接入使用
@version 0.1.0
@date    2026.09.14
@usage
本库是 GB28181 设备侧(下级设备/前端设备)的高层封装。

分层约定：
  C 层  gb28181        —— luatos-ext-components/gb28181，负责协议编解码
                          (PS 封装 / RTP 打包 / SIP 报文解析构造 / MANSCDP XML)
  Lua 层 exgb28181.lua —— 本文件，负责业务状态机与用户 API
                          (注册、心跳、查询响应、点播会话管理)

基本用法：
local exgb28181 = require "exgb28181"

-- 1、注册统一事件回调
exgb28181.on(function(event, action, data)
    if event == "register" then
        log.info("gb28181", "注册状态", action)
    elseif event == "invite" and action == "incoming" then
        log.info("gb28181", "平台请求点播", data.channel_id)
    end
end)

-- 2、配置设备参数
exgb28181.init({
    device_id       = "34020000001320000001", -- 20 位国标设备编码
    sip_server_addr = "192.168.1.100",
    sip_server_port = 5060,
    sip_domain      = "3402000000",
    sip_password    = "12345678",
    transport       = "udp",
})

-- 3、启动服务
exgb28181.start()

-- 4、停止服务
-- exgb28181.stop()
]]

local exgb28181 = {}

-- C 层模块句柄，首次使用时加载。
-- 采用延迟加载而非模块顶层 require，原因有两个：
--   1、固件若未开启 LUAT_USE_GB28181，require "exgb28181" 本身不应失败，
--      便于在 PC 模拟器上单独调试 Lua 层逻辑；
--   2、调试时可用桩模块替换 C 层，无需重编固件。
local g_core = nil
local g_core_loaded = false

local g_config = nil
local g_started = false
local g_callback = nil

local default_config = {
    sip_server_port = 5060,
    sip_domain      = nil,
    transport       = "udp",
    local_port      = 5060,
    device_name     = "LuatOS GB28181 Device",
    manufacturer    = "LuatOS",
    model           = "LuatOS",
    firmware        = "V1.0",
    keepalive       = 60,
    register_expires = 3600,
    channels        = nil,
}

local function log_info(...)
    if _G.log and type(log.info) == "function" then
        log.info("exgb28181", ...)
    end
end

local function log_warn(...)
    if _G.log and type(log.warn) == "function" then
        log.warn("exgb28181", ...)
    end
end

local function log_error(...)
    if _G.log and type(log.error) == "function" then
        log.error("exgb28181", ...)
    end
end

--[[
加载 C 层 gb28181 模块。加载失败时返回 nil 而非抛错。

两条取用路径：
  1、require "gb28181" —— 真机固件上的常规路径
  2、全局表 _G.gb28181 —— PC 模拟器的回退路径。该模拟器用自定义加载器
     接管了 require(做脚本依赖裁剪)，不解析 C 内建模块，require 必然失败，
     但 luaL_requiref 仍会把模块挂到全局表上。

注意：rotable 风格模块(luat_newlib2)的 type 是 "userdata" 而非 "table"，
因此这里不能按 table 判断。
@return table|userdata|nil C 层模块
]]
local function load_core()
    if g_core_loaded then
        return g_core
    end
    g_core_loaded = true

    local ok, mod = pcall(require, "gb28181")
    if not ok then
        mod = rawget(_G, "gb28181")
    end

    if mod == nil then
        log_warn("C 层 gb28181 模块不可用，请确认固件已开启 LUAT_USE_GB28181")
        g_core = nil
    else
        g_core = mod
    end
    return g_core
end

--[[
向用户回调派发事件。回调内部异常不会向外抛出，避免打断协议任务。
@api exgb28181.on 的回调原型
@string event 事件大类，如 "register"、"invite"、"media"、"catalog"
@string action 动作，如 "ok"、"incoming"、"ready"、"ended"
@table data 事件负载
]]
local function emit(event, action, data)
    if type(g_callback) ~= "function" then
        return
    end
    local ok, err = pcall(g_callback, event, action, data or {})
    if not ok then
        log_error("事件回调异常", event, action, err)
    end
end

--[[
校验 20 位国标设备编码。
编码规则(GB/T 28181-2016 附录D)：8 位中心编码 + 2 位行业编码 +
3 位类型编码 + 4 位网络标识 + 3 位序号。
@api (内部函数)
@string id 待校验的编码
@return boolean true 表示合法
]]
local function is_valid_device_id(id)
    if type(id) ~= "string" then
        return false
    end
    if #id ~= 20 then
        return false
    end
    return id:match("^%d+$") ~= nil
end

--[[
校验 SIP 账号配置，返回规范化后的配置表。
校验失败的字段通过第二个返回值给出原因，便于上层定位。
@api (内部函数)
@table config 用户传入的配置
@return table|nil 规范化配置
@return string|nil 失败原因
]]
local function validate_config(config)
    if type(config) ~= "table" then
        return nil, "config 必须是 table"
    end

    if not is_valid_device_id(config.device_id) then
        return nil, "device_id 必须是 20 位数字的国标编码"
    end

    if type(config.sip_server_addr) ~= "string" or #config.sip_server_addr == 0 then
        return nil, "sip_server_addr 必须是非空字符串"
    end

    if config.sip_password ~= nil and type(config.sip_password) ~= "string" then
        return nil, "sip_password 必须是字符串"
    end

    local transport = config.transport or default_config.transport
    transport = tostring(transport):lower()
    if transport ~= "udp" and transport ~= "tcp" then
        return nil, "transport 只支持 udp 或 tcp"
    end

    local port = config.local_port or default_config.local_port
    if type(port) ~= "number" or port < 1 or port > 65535 then
        return nil, "local_port 必须是 1~65535 的端口号"
    end

    local merged = {}
    for k, v in pairs(default_config) do
        merged[k] = v
    end
    for k, v in pairs(config) do
        merged[k] = v
    end
    merged.transport = transport
    merged.local_port = port
    -- 未显式配置域时，按国标惯例取设备编码的前 10 位
    if not merged.sip_domain or #merged.sip_domain == 0 then
        merged.sip_domain = merged.device_id:sub(1, 10)
    end

    return merged
end

--[[
注册统一事件回调。
@api exgb28181.on(callback)
@function callback 回调函数，原型为 callback(event, action, data)
@return boolean 成功返回 true
@usage
exgb28181.on(function(event, action, data)
    log.info("gb28181", event, action)
end)
]]
function exgb28181.on(callback)
    if callback ~= nil and type(callback) ~= "function" then
        return false
    end
    g_callback = callback
    return true
end

--[[
初始化 GB28181 设备参数。
只做参数校验与保存，不产生任何网络行为；网络行为由 start() 触发。
@api exgb28181.init(config)
@table config 配置表，必填字段见下
@return boolean 成功返回 true，失败返回 false
@return string|nil 失败原因
@usage
exgb28181.init({
    device_id       = "34020000001320000001",
    sip_server_addr = "192.168.1.100",
    sip_server_port = 5060,
    sip_domain      = "3402000000",
    sip_password    = "12345678",
})
]]
function exgb28181.init(config)
    local merged, err = validate_config(config)
    if not merged then
        log_error("配置校验失败", err)
        return false, err
    end

    if g_started then
        return false, "服务已启动，请先调用 stop()"
    end

    g_config = merged
    log_info("初始化完成", "device_id", merged.device_id,
             "server", merged.sip_server_addr .. ":" .. merged.sip_server_port,
             "transport", merged.transport)
    emit("lifecycle", "init", {
        device_id = merged.device_id,
        server    = merged.sip_server_addr,
        port      = merged.sip_server_port,
        transport = merged.transport,
    })
    return true
end

--[[
启动 GB28181 服务。
@api exgb28181.start()
@return boolean 成功返回 true，失败返回 false
@return string|nil 失败原因
]]
function exgb28181.start()
    if g_started then
        return false, "服务已启动"
    end
    if not g_config then
        return false, "请先调用 init() 完成配置"
    end

    -- 里程碑 M2 实现：SIP 注册、心跳保活、查询响应
    return false, "尚未实现(里程碑 M2)"
end

--[[
停止 GB28181 服务并释放资源。
@api exgb28181.stop()
@return boolean 成功返回 true
]]
function exgb28181.stop()
    if not g_started then
        return true
    end
    g_started = false
    log_info("服务已停止")
    emit("lifecycle", "stop")
    return true
end

--[[
获取当前生效的配置表副本。
@api exgb28181.get_config()
@return table|nil 配置表，未初始化时返回 nil
]]
function exgb28181.get_config()
    if not g_config then
        return nil
    end
    local copy = {}
    for k, v in pairs(g_config) do
        copy[k] = v
    end
    return copy
end

--[[
查询服务是否已启动。
@api exgb28181.is_started()
@return boolean 已启动返回 true
]]
function exgb28181.is_started()
    return g_started
end

--[[
查询 C 层 gb28181 模块是否可用。
固件未开启 LUAT_USE_GB28181、或在没有该 C 模块的环境(如纯 Lua 调试)下返回 false。
@api exgb28181.has_core()
@return boolean C 层可用返回 true
]]
function exgb28181.has_core()
    return load_core() ~= nil
end

--[[
获取版本号。优先返回 C 层版本，C 层不可用时返回 Lua 层版本。
@api exgb28181.version()
@return string 版本号字符串
@usage
log.info("gb28181", exgb28181.version())
]]
function exgb28181.version()
    local core = load_core()
    if core and type(core.version) == "function" then
        return core.version()
    end
    return "0.1.0-lua"
end

return exgb28181
