--[[
@module  param_field
@summary TCP 主站应用模块（字段参数方式）
@version 1.0
@date    2025.12.30
@author  马梦阳
@usage
本功能模块演示的内容为：
1、将设备配置为 modbus TCP 主站模式
2、与从站 1 和 从站 2 进行通信
    1. 对从站 1 进行 2 秒一次的读取保持寄存器 0-1 操作
    2. 对从站 2 进行 4 秒一次的写入保持寄存器 0-1 操作

注意事项：
1、该示例程序需要搭配 exmodbus 扩展库使用
2、本功能模块适合使用标准 modbus TCP 请求报文格式的用户
3、如果你使用的是非标准 modbus TCP 请求报文格式，请参考 raw_frame 功能模块

本文件没有对外接口,直接在 main.lua 中 require "param_field" 就可以加载运行；
]]

local exmodbus = require("exmodbus")

-- 创建 TCP 主站配置参数
-- 说明：创建 TCP 主站时只需要配置如下参数即可
local create_config = {
    -- 网络参数配置
    mode = exmodbus.TCP_MASTER,   -- 通信模式：TCP主站
    adapter = socket.LWIP_ETH,    -- 网卡 ID：LwIP 协议栈的以太网卡
    ip_address = "192.168.1.100", -- 从站 IP 地址
    port = 6000,                  -- 从站端口号
}

-- 初始化从站 1 数据结构
-- 用于记录从站 1 保持寄存器 0-1 的值
local slave1_data = {}

-- 读取从站 1 保持寄存器 0-1 的值时，配置读命令的字段参数；
local read_config = {
    slave_id = 1,                         -- 从站地址 1
    reg_type = exmodbus.HOLDING_REGISTER, -- 寄存器类型：保持寄存器
    start_addr = 0x0000,                  -- 起始地址 0
    reg_count = 0x0002,                   -- 读取 2 个寄存器
    timeout = 1000                        -- 超时时间 1000 ms
}


-- 初始化从站 2 数据结构；
local slave2_data = {
    data1 = 123,
    data2 = 456
}

-- 定义从站 2 保持寄存器的起始地址；
local start_addr = 0x0000

-- 写入从站 2 保持寄存器 0-1 的值时，配置写命令的字段参数；
local write_config = {
    slave_id = 2,                                            -- 从站地址 2
    reg_type = exmodbus.HOLDING_REGISTER,                    -- 寄存器类型：保持寄存器
    start_addr = start_addr,                                 -- 起始地址 0
    reg_count = 0x0002,                                      -- 写入 2 个寄存器
    data = {
        [start_addr] = slave2_data.data1,                    -- 第一个寄存器值
        [start_addr + 1] = slave2_data.data2,                -- 第二个寄存器值
    },                                                       -- 写入寄存器值
    force_multiple = true,                                   -- 强制使用写多个功能码
                                                                -- 设置为 true 时，写单个或多个线圈时强制功能码为 0x0F，写单个或多个保持寄存器时强制功能码为 0x10
                                                                -- 设置为 false 时，写单个线圈时功能码为 0x05，写单个保持寄存器时功能码为 0x06，写多个线圈时功能码为 0x0F，写多个保持寄存器时功能码为 0x10
    timeout = 1000                                           -- 超时时间 1000 ms
}


-- 创建 TCP 主站实例
local tcp_master = exmodbus.create(create_config)

-- 判断主站是否创建成功并记录日志
if not tcp_master then
    log.info("exmodbus_test", "tcp_master 创建失败")
else
    log.info("exmodbus_test", "tcp_master 创建成功")
end


-- 读取从站 1 保持寄存器数据的函数
local function read_slave1_holding_registers()

    log.info("exmodbus_test", "开始读取从站 1 保持寄存器 0-1 的值")

    -- 执行读取操作
    local read_result = tcp_master:read(read_config)

    -- 根据返回状态处理结果
    if read_result.status == exmodbus.STATUS_SUCCESS then
        slave1_data.data1 = read_result.data[read_config.start_addr]
        slave1_data.data2 = read_result.data[read_config.start_addr + 1]
        log.info("exmodbus_test", "成功读取到从站 1 保持寄存器 0-1 的值，寄存器 0 数值为", slave1_data.data1, "，寄存器 1 数值为", slave1_data.data2)
    elseif read_result.status == exmodbus.STATUS_DATA_INVALID then
        log.info("exmodbus_test", "收到从站 1 的响应数据但数据损坏/校验失败")
    elseif read_result.status == exmodbus.STATUS_EXCEPTION then
        log.info("exmodbus_test", "收到从站 1 的 modbus 标准异常响应，异常码为", read_result.execption_code)
    elseif read_result.status == exmodbus.STATUS_TIMEOUT then
        log.info("exmodbus_test", "未收到从站 1 的响应（超时）")
    end
end

-- 写入从站 2 保持寄存器数据的函数
local function write_slave2_holding_registers()

    log.info("exmodbus_test", "开始写入从站 2 保持寄存器 0-1 的值，寄存器 0 数值为", slave2_data.data1, "，寄存器 1 数值为", slave2_data.data2)

    -- 执行写入操作
    local write_result = tcp_master:write(write_config)

    -- 根据返回状态处理结果
    if write_result.status == exmodbus.STATUS_SUCCESS then
        log.info("exmodbus_test", "成功写入从站 2 保持寄存器 0-1 的值")
    elseif write_result.status == exmodbus.STATUS_DATA_INVALID then
        log.info("exmodbus_test", "收到从站 2 的响应数据但数据损坏/校验失败")
    elseif write_result.status == exmodbus.STATUS_EXCEPTION then
        log.info("exmodbus_test", "收到从站 2 的 modbus 标准异常响应，异常码为", write_result.execption_code)
    elseif write_result.status == exmodbus.STATUS_TIMEOUT then
        log.info("exmodbus_test", "未收到从站 2 的响应（超时）")
    end
end

-- 定时任务函数：每 2 秒调用一次读取函数，每 4 秒调用一次写入函数
local function task()

    local count = 0 -- 计数器

    while true do
        if tcp_master then
            -- 每 2 秒调用一次读取函数
            read_slave1_holding_registers()
            if count == 0 then
                -- 每 4 秒调用一次写入函数
                write_slave2_holding_registers()
            end
            count = (count + 1) % 2
        else
            log.info("exmodbus_test", "tcp_master 未创建，无法执行 read_slave1_holding_registers()")
        end
        sys.wait(2000)
    end
end

-- 初始化任务
sys.taskInit(task)
