--[[
@module  raw_frame
@summary TCP 主站应用模块（原始帧方式）
@version 1.0
@date    2026.01.04
@author  马梦阳
@usage
本功能模块演示的内容为：
1、将设备配置为 modbus TCP 主站模式
2、与从站 1 和 从站 2 进行通信
    1. 对从站 1 进行 2 秒一次的读取保持寄存器 0-1 操作
    2. 对从站 2 进行 4 秒一次的写入保持寄存器 0-1 操作

注意事项：
1、该示例程序需要搭配 exmodbus 扩展库使用
2、本功能模块只适合使用非标准 modbus TCP 请求报文格式的用户
3、如果你使用的是标准 modbus TCP 请求报文格式，请参考 param_field 功能模块

本文件没有对外接口,直接在 main.lua 中 require "raw_frame" 就可以加载运行；
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
-- 用于记录从站 1 保持寄存器 0-1 的值；
local slave1_data = {}

-- 配置读取从站 1 保持寄存器 0-1 的值；
local read_config = {
    raw_request = string.char(
        0x00, 0x01, -- 事务标识符
        0x00, 0x00, -- 协议标识符
        0x00, 0x06, -- 长度
        0x01,       -- 单元标识符（从站地址）
        0x03,       -- 功能码：读取保持寄存器
        0x00, 0x00, -- 寄存器起始地址
        0x00, 0x02  -- 寄存器数量
    ),
    timeout = 1000  -- 超时时间 1000 ms
}

-- 配置写入从站 2 保持寄存器 0-1 的值；
local write_config = {
    raw_request = string.char(
        0x00, 0x02, -- 事务标识符
        0x00, 0x00, -- 协议标识符
        0x00, 0x0B, -- 长度
        0x02,       -- 单元标识符（从站地址）
        0x10,       -- 功能码：写入保持寄存器
        0x00, 0x00, -- 寄存器起始地址
        0x00, 0x02, -- 寄存器数量
        0x04,       -- 字节数量
        0x00, 0x12, -- 寄存器 0 的值
        0x00, 0x34  -- 寄存器 1 的值
    ),
    timeout = 1000  -- 超时时间 1000 ms
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
        local resp = read_result.raw_response

        -- 特别说明：
        -- 接下来的判断是针对 modbus TCP 标准响应格式的应答原始帧来解析的
        -- 在实际项目中，应根据自己项目中的实际应答原始帧格式进行解析
        -- 如果实际格式与此处演示的格式不一致，需要修改接下来的解析代码

        -- 1. 检查总长度：必须为 13 字节（7 MBAP头 + 1 功能码 + 1 字节数 + 4 数据）
        if #resp ~= 13 then
            log.info("exmodbus_test", "响应长度错误，期望 13 字节，实际:", #resp)
            return
        end

        -- 2. 检查事务标识符是否与请求一致
        local req_trans_id = string.unpack(">I2", read_config.raw_request, 1)
        local resp_trans_id = string.unpack(">I2", resp, 1)
        if req_trans_id ~= resp_trans_id then
            log.info("exmodbus_test", "事务标识符不一致，期望:", req_trans_id, "实际:", resp_trans_id)
            return
        end

        -- 3. 检查协议标识符是否为 0x0000
        if string.unpack(">I2", resp, 3) ~= 0x0000 then
            log.info("exmodbus_test", "协议标识符错误，期望 0x0000，实际:", string.unpack(">I2", resp, 3))
            return
        end

        -- 4. 检查单元标识符（从站地址）是否与请求一致
        local req_unit_id = string.byte(read_config.raw_request, 7)
        local resp_unit_id = string.byte(resp, 7)
        if req_unit_id ~= resp_unit_id then
            log.info("exmodbus_test", "单元标识符不一致，期望:", req_unit_id, "实际:", resp_unit_id)
            return
        end

        -- 5. 检查功能码是否与请求一致
        local req_func_code = string.byte(read_config.raw_request, 8)
        local resp_func_code = string.byte(resp, 8)
        if req_func_code ~= resp_func_code then
            log.info("exmodbus_test", "功能码不一致，期望:", req_func_code, "实际:", resp_func_code)
            return
        end

        -- 6. 检查字节数字段是否正确
        local byte_count = string.byte(resp, 9)
        if byte_count ~= 4 then
            log.info("exmodbus_test", "字节数字段错误，期望 4 字节，实际:", byte_count)
            return
        end

        -- 7. 解析寄存器数据（从第 10 字节开始，大端序）
        local data1 = string.unpack(">I2", resp, 10) -- 寄存器 0，偏移 10
        local data2 = string.unpack(">I2", resp, 12) -- 寄存器 1，偏移 12

        -- 8. 记录数据
        slave1_data[0] = data1
        slave1_data[1] = data2

        -- 9. 记录日志
        log.info("exmodbus_test", "成功读取到从站 1 保持寄存器 0-1 的值，寄存器 0 数值为", slave1_data[0], "，寄存器 1 数值为", slave1_data[1])
    elseif read_result.status == exmodbus.STATUS_TIMEOUT then
        log.info("exmodbus_test", "未收到从站 1 的响应（超时）")
    elseif read_result.status == exmodbus.STATUS_PARAM_INVALID then
        log.info("exmodbus_test", "读取从站 1 参数无效")
    end
end

-- 写入从站 2 保持寄存器数据的函数
local function write_slave2_holding_registers()

    log.info("exmodbus_test", "开始写入从站 2 保持寄存器 0-1 的值")

    -- 执行写入操作
    local write_result = tcp_master:write(write_config)

    -- 根据返回状态处理结果
    if write_result.status == exmodbus.STATUS_SUCCESS then
        local resp = write_result.raw_response

        -- 特别说明：
        -- 接下来的判断是针对 modbus TCP 标准响应格式的应答原始帧来解析的
        -- 在实际项目中，应根据自己项目中的实际应答原始帧格式进行解析
        -- 如果实际格式与此处演示的格式不一致，需要修改接下来的解析代码

        -- 1. 检查总长度：必须为 12 字节（7 MBAP头 + 1 功能码 + 2 起始地址 + 2 寄存器数量）
        if #resp ~= 12 then
            log.info("exmodbus_test", "响应长度错误，期望 12 字节，实际:", #resp)
            return
        end

        -- 2. 检查事务标识符是否与请求一致
        local req_trans_id = string.unpack(">I2", write_config.raw_request, 1)
        local resp_trans_id = string.unpack(">I2", resp, 1)
        if req_trans_id ~= resp_trans_id then
            log.info("exmodbus_test", "事务标识符不一致，期望:", req_trans_id, "实际:", resp_trans_id)
            return
        end

        -- 3. 检查协议标识符是否为 0x0000
        if string.unpack(">I2", resp, 3) ~= 0x0000 then
            log.info("exmodbus_test", "协议标识符错误，期望 0x0000，实际:", string.unpack(">I2", resp, 3))
            return
        end

        -- 4. 检查单元标识符（从站地址）是否与请求一致
        local req_unit_id = string.byte(write_config.raw_request, 7)
        local resp_unit_id = string.byte(resp, 7)
        if req_unit_id ~= resp_unit_id then
            log.info("exmodbus_test", "单元标识符不一致，期望:", req_unit_id, "实际:", resp_unit_id)
            return
        end

        -- 5. 检查功能码是否与请求一致
        local req_func_code = string.byte(write_config.raw_request, 8)
        local resp_func_code = string.byte(resp, 8)
        if req_func_code ~= resp_func_code then
            log.info("exmodbus_test", "功能码不一致，期望:", req_func_code, "实际:", resp_func_code)
            return
        end

        -- 6. 检查起始地址是否与请求一致
        local req_start_addr = string.unpack(">I2", write_config.raw_request, 9)
        local resp_start_addr = string.unpack(">I2", resp, 9)
        if req_start_addr ~= resp_start_addr then
            log.info("exmodbus_test", "起始地址不一致，期望:", req_start_addr, "实际:", resp_start_addr)
            return
        end

        -- 7. 检查寄存器数量是否与请求一致
        local req_reg_count = string.unpack(">I2", write_config.raw_request, 11)
        local resp_reg_count = string.unpack(">I2", resp, 11)
        if req_reg_count ~= resp_reg_count then
            log.info("exmodbus_test", "寄存器数量不一致，期望:", req_reg_count, "实际:", resp_reg_count)
            return
        end

        log.info("exmodbus_test", "成功写入从站 2 保持寄存器 0-1")
    elseif write_result.status == exmodbus.STATUS_TIMEOUT then
        log.info("exmodbus_test", "未收到从站 2 的响应（超时）")
    elseif write_result.status == exmodbus.STATUS_PARAM_INVALID then
        log.info("exmodbus_test", "写入从站 2 参数无效")
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
