-- uart_setup_first.lua
-- 通用的第一个UART配置模块（用于发送端）

local uart_id = nil  -- 由调用方注入
local uart_received = false

-- 设置UART的函数
local function setup_uart(id, baud_rate, data_bit, stop_bit, parity, bit_order, buff)
    uart_id = id
    local result = uart.setup(id, baud_rate, data_bit, stop_bit, parity, bit_order, buff)
    print(string.format(
        "uart%d.setup(波特率 %d, 数据位 %d, 停止位 %s, 校验位 %s, 大小端 %s, 缓冲区大小 %d) = 设置结果 %d",
        id, baud_rate, data_bit, stop_bit, tostring(parity), tostring(bit_order), buff, result))
    return result
end

-- 注册UART事件的函数
local function setup_uart_event(test_data)
    uart.on(uart_id, "receive", function(id, len)
        -- 第一次读取
        local data = uart.read(id, len)
        log.info(string.format("uart%d接收到的数据", id), len, data)
        
        -- 检查缓冲区是否还有剩余数据
        local size = uart.rxSize(id)
        if size == 0 then
            assert(data == test_data,
                string.format("uart%d接收数据失败 [配置: %s] : 预期 '%s'(%d字节), 实际 '%s'(%d字节)",
                    id, config_info, test_data, #test_data, data, #data))
        else
            log.info(string.format("uart%d接收后缓冲区剩余", id), size, "字节")
            local all_data = data
            local total_len = len
            -- 如果缓冲区还有数据，继续读取
            while size > 0 do
                log.info(string.format("uart%d缓冲区余量不为0", id))
                local more_data = uart.read(id, size)
                log.info(string.format("uart%d继续读取", id), size, "字节:", more_data)

                if more_data then
                    all_data = all_data .. more_data
                    total_len = total_len + #more_data
                end
                -- 再次检查缓冲区
                size = uart.rxSize(id)
                log.info(string.format("uart%d缓冲区剩余", id), size, "字节")
            end

            assert(all_data == test_data,
                string.format("uart%d接收数据失败 [配置: %s] : 预期 '%s'(%d字节), 实际 '%s'(%d字节)",
                    id, config_info, test_data, #test_data, all_data, total_len))
        end
        uart_received = true
        sys.publish("UART_RECEIVE_OK_" .. id)
    end)
end

local function get_uart_received()
    return uart_received
end

local function clean_uart_status()
    uart_received = false
end

return {
    setup_uart = setup_uart,
    setup_uart_event = setup_uart_event,
    get_uart_received = get_uart_received,
    clean_uart_status = clean_uart_status,
}