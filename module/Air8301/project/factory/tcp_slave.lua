--[[
@module  tcp_slave
@summary 网口2 TCP Modbus 从站（8301出厂固件）
@version 1.0
@date    2026.09.22
@author  江访
@usage
本功能模块实现：
1、配置网口2为 Modbus TCP 从站模式
2、监听 TCP 连接，被动应答电脑主站的读写请求
3、复用 rtu_slave_regmap.lua 中的寄存器映射表

网口配置：
- 适配器：socket.LWIP_USER1（CH390H 网口2，CS=GPIO5）
- IP地址：192.168.1.185（静态）
- 端口：502（标准Modbus TCP端口）
- 从站地址：1

注意事项：
1、该模块需要搭配 exmodbus 扩展库使用
2、需要先 require "net_drv" 启动以太网
3、需要在 main.lua 中先 require "rtu_slave_regmap" 加载寄存器映射表

本文件没有对外接口，直接在 main.lua 中 require "tcp_slave" 就可以加载运行；
]]

local exmodbus = require("exmodbus")

-- 等待网口2网络就绪标志
local network_ready = false

-- TCP从站实例
local tcp_slave = nil

-- 从 rtu_slave_regmap 模块获取回调函数
local modbus_callback = nil
local rtu_regmap = nil

--[[
把从站响应转为可读 hex 文本

@local
@function resp_to_hex
@param resp table 响应数据表（索引为地址，值为寄存器数值）
@return string hex 文本
]]
local function resp_to_hex(resp)
    local hex = ""
    for addr, v in pairs(resp) do
        if type(addr) == "number" then
            hex = hex .. string.format("%02X %02X ", (v >> 8) & 0xFF, v & 0xFF)
        end
    end
    return hex
end

--[[
TCP 从站请求回调包装：转发给 regmap 回调，并发布监视消息

@local
@function tcp_slave_callback
@param req table Modbus 请求
@return table 响应数据表
]]
local function tcp_slave_callback(req)
    local resp = modbus_callback(req)
    if resp and type(resp) == "table" then
        local req_hex = string.format("%02X %02X %02X %02X %02X %02X",
            req.slave_id, req.func_code,
            (req.start_addr >> 8) & 0xFF, req.start_addr & 0xFF,
            (req.reg_count >> 8) & 0xFF, req.reg_count & 0xFF)
        sys.publish("MODBUS_TCP_LOG", string.format("[TCP] 请求:%s  应答:%s",
            req_hex, resp_to_hex(resp)))
    end
    return resp
end

--[[
IP_READY 回调：网口2就绪

@local
@function on_ip_ready
@param ip string IP地址
@param adapter number 网卡编号
]]
local function on_ip_ready(ip, adapter)
    if adapter == socket.LWIP_USER1 then
        network_ready = true
        log.info("tcp_slave", "网口2网络就绪，IP地址:", ip)
    end
end

--[[
TCP 从站初始化任务：等待 regmap 就绪后创建 TCP 从站并注册回调

@local
@function tcp_slave_task
]]
local function tcp_slave_task()
    -- 等待系统初始化
    sys.wait(1000)

    -- 尝试获取 rtu_slave_regmap 导出的回调
    rtu_regmap = require("rtu_slave_regmap")
    if rtu_regmap and rtu_regmap.get_callback then
        modbus_callback = rtu_regmap.get_callback()
        log.info("tcp_slave", "成功获取寄存器回调")
    else
        log.error("tcp_slave", "未找到 rtu_slave_regmap 模块的回调函数")
    end

    -- 创建 TCP 从站配置
    local create_config = {
        mode = exmodbus.TCP_SLAVE,        -- TCP从站模式
        adapter = socket.LWIP_USER1,      -- 网口2（CH390H）
        port = 502,                       -- 标准Modbus TCP端口
        slave_id = 1,                     -- 从站地址（与RTU从站一致）
    }

    -- 创建 TCP 从站实例
    tcp_slave = exmodbus.create(create_config)

    if not tcp_slave then
        log.error("tcp_slave", "TCP从站创建失败")
    else
        log.info("tcp_slave", "TCP从站创建成功，监听端口:", create_config.port)
    end

    -- 注册回调函数（转发给 regmap 回调）
    if tcp_slave and modbus_callback then
        tcp_slave:on(tcp_slave_callback)
        log.info("tcp_slave", "Modbus回调注册成功")
    elseif tcp_slave then
        log.warn("tcp_slave", "Modbus回调未注册，请在 rtu_slave_regmap 中导出回调")
    end
end

sys.taskInit(tcp_slave_task)
sys.subscribe("IP_READY", on_ip_ready)

log.info("tcp_slave", "TCP从站模块加载完成")
log.info("tcp_slave", "连接信息: IP 192.168.1.185  端口 502  从站地址 1")
