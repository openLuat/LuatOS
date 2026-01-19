-- uart1_setup.lua
-- 设置uart1的函数
local function setup_uart1(baud_rate, data_bit, stop_bit, parity, bit_order, buff)
    local result1 = uart.setup(1, baud_rate, data_bit, stop_bit, parity, bit_order, buff)
    print(string.format(
        "uart1.setup(uartid %d, 波特率 %d, 数据位 %d, 停止位 %s, 校验位 %s, 大小端 %s, 缓冲区大小 %d) = 设置结果%d",
        1, baud_rate, data_bit, stop_bit, tostring(parity), tostring(bit_order), buff, result1))
    return result1
end

local test_data = "Hello UART Loopback!\r\n"

local uart1_received 
-- 注册uart1事件的函数
local function setup_uart1_event()

    uart.on(1, "receive", function(id, len)
        -- 第一次读取
        local data = uart.read(id, len)
        log.info("uart1第接收到的数据", id, len, data)
        -- 检查缓冲区是否还有剩余数据
        local size = uart.rxSize(id)
        if size == 0 then
            assert(data == test_data,
                string.format("uart1接收数据失败 [配置: %s] : 预期 '%s'(%d字节), 实际 '%s'(%d字节)",
                    config_info, test_data, #test_data, data, #data))
        else
        log.info("uart1接收后缓冲区剩余", size, "字节")
            local all_data = data
            local total_len = len
            -- 如果缓冲区还有数据，继续读取
            while size > 0 do
                log.info("uart1缓冲区余量不为0")
                local more_data = uart.read(id, size)
                log.info("uart1继续读取", size, "字节:", more_data)

                if more_data then
                    all_data = all_data .. more_data
                    total_len = total_len + #more_data
                end
                -- 再次检查缓冲区
                size = uart.rxSize(id)
                log.info("uart1缓冲区剩余", size, "字节")
            end

            assert(all_data == test_data,
                string.format("uart1接收数据失败 [配置: %s] : 预期 '%s'(%d字节), 实际 '%s'(%d字节)",
                    config_info, test_data, #test_data, all_data, total_len))
        end
        uart1_received = true
        sys.publish("UART1_RECEIVE_OK")
    end)
end

local function get_uart1_received()
    return uart1_received
end
-- 获取测试状态

local function clean_uart1_status()
    uart1_received =false
end

-- 获取完整数据

return {
    setup_uart1 = setup_uart1,
    setup_uart1_event = setup_uart1_event,
    get_uart1_received =get_uart1_received,
    clean_uart1_status =clean_uart1_status,
}
