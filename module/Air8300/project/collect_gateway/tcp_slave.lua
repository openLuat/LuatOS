--[[
@module  tcp_slave
@summary 网口2 TCP Modbus 从站
@version 1.0
@date    2026.05.19
@author  马梦阳
@usage
本功能模块实现：
1、配置网口2为 Modbus TCP 从站模式
2、监听 TCP 连接，被动应答电脑主站的读写请求
3、复用 rtu_slave_regmap.lua 中的寄存器映射表

网口配置：
- 适配器：socket.LWIP_USER1（CH390_2）
- IP地址：192.168.1.185（静态）
- 端口：502（标准Modbus TCP端口）
- 从站地址：1

注意事项：
1、该模块需要搭配 exmodbus 扩展库使用
2、需要先 require "netdrv_eth_static" 启动以太网
3、需要在 main.lua 中先 require "rtu_slave_regmap" 加载寄存器映射表

本文件没有对外接口，直接在 main.lua 中 require "tcp_slave" 就可以加载运行；

本文件是被动从站模块，对外通过 Modbus TCP 协议响应主站请求：
1、订阅 "IP_READY"，等待网口2网络就绪后启动监听
2、从 rtu_slave_regmap 获取寄存器读写回调，供外部 Modbus 主站读取
]]

local exmodbus = require("exmodbus")

-- 等待网口2网络就绪标志
local network_ready = false

-- TCP从站实例
local tcp_slave = nil

-- 从 rtu_slave_regmap 模块获取回调函数
local modbus_callback = nil

sys.taskInit(function()
    -- 等待系统初始化
    sys.wait(1000)
    
    -- 尝试获取 rtu_slave_regmap 导出的回调
    local rtu_regmap = require("rtu_slave_regmap")
    if rtu_regmap and rtu_regmap.get_callback then
        modbus_callback = rtu_regmap.get_callback()
        log.info("tcp_slave", "成功获取寄存器回调")
    else
        log.error("tcp_slave", "未找到 rtu_slave_regmap 模块的回调函数")
    end
    
    -- 创建 TCP 从站配置
    local create_config = {
        mode = exmodbus.TCP_SLAVE,        -- TCP从站模式
        adapter = socket.LWIP_USER1,       -- 网口2（CH390_2）
        port = 502,                        -- 标准Modbus TCP端口
        slave_id = 1,                      -- 从站地址（与RTU从站一致）
    }
    
    -- 创建 TCP 从站实例
    tcp_slave = exmodbus.create(create_config)
    
    if not tcp_slave then
        log.error("tcp_slave", "TCP从站创建失败")
    else
        log.info("tcp_slave", "TCP从站创建成功，监听端口:", create_config.port)
        log.info("tcp_slave", "等待电脑主站连接...")
    end
    
    -- 注册回调函数
    if tcp_slave and modbus_callback then
        tcp_slave:on(modbus_callback)
        log.info("tcp_slave", "Modbus回调注册成功")
    elseif tcp_slave then
        log.warn("tcp_slave", "Modbus回调未注册，请在 rtu_slave_regmap 中导出回调")
    end
    
    -- 连接状态监控任务
    while true do
        if network_ready and tcp_slave then
            -- TCP从站会自动处理连接，这里只是记录状态
        end
        sys.wait(10000)  -- 每10秒检查一次
    end
end)

-- 订阅网络就绪事件
sys.subscribe("IP_READY", function(ip, adapter)
    if adapter == socket.LWIP_USER1 then
        network_ready = true
        log.info("tcp_slave", "网口2网络就绪，IP地址:", ip)
    end
end)

log.info("tcp_slave", "TCP从站模块加载完成")
log.info("tcp_slave", "连接信息:")
log.info("tcp_slave", "  IP: 192.168.1.185")
log.info("tcp_slave", "  端口: 502")
log.info("tcp_slave", "  从站地址: 1")
