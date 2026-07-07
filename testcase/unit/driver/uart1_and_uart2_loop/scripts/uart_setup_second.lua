-- uart_setup_second.lua
-- 通用的第二个UART配置模块（用于接收并回传端）

local uart_id = nil  -- 由调用方注入

-- 设置UART的函数
local function setup_uart(id, baud_rate, data_bit, stop_bit, parity, bit_order, buff)
    uart_id = id
    local result = uart.setup(id, baud_rate, data_bit, stop_bit, parity, bit_order, buff)
    print(string.format(
        "uart%d.setup(波特率 %d, 数据位 %d, 停止位 %s, 校验位 %s, 大小端 %s, 缓冲区大小 %d) = 设置结果 %d",
        id, baud_rate, data_bit, stop_bit, tostring(parity), tostring(bit_order), buff, result))
    return result
end

-- 注册UART事件的函数（接收数据后回传）
local function setup_uart_event(expected_data)
    uart.on(uart_id, "receive", function(id, len)
        -- 第一次读取
        local data = uart.read(id, len)
        log.info(string.format("uart%d接收到的数据", id), len, data)
        
        -- 检查缓冲区是否还有剩余数据
        local size = uart.rxSize(id)
        if size == 0 then
            assert(data == expected_data,
                string.format("uart%d接收数据失败 [配置: %s] : 预期 '%s'(%d字节), 实际 '%s'(%d字节)",
                    id, config_info, expected_data, #expected_data, data, #data))
        else
            log.info(string.format("uart%d接收后缓冲区剩余", id), size, "字节")
            local all_data = data
            local total_len = len
            -- 如果缓冲区还有数据，继续读取
            while size > 0 do
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

            -- UART数据接收断言
            assert(all_data == expected_data,
                string.format("uart%d接收数据失败 [配置: %s] : 预期 '%s'(%d字节), 实际 '%s'(%d字节)",
                    id, config_info, expected_data, #expected_data, all_data, total_len))
        end
        
        -- 将接收到的数据回写到第一个UART（回环）
        local uart_write_data = uart.write(id, expected_data)
        log.info(string.format("再将uart%d收到的数据还回去", id), uart_write_data)

        -- UART发送数据断言
        assert(uart_write_data == #expected_data, string.format(
            "uart%d发送数据失败 [配置: %s] : 预期 %d, 实际 %d", id, config_info, #expected_data, uart_write_data))
    end)
end

return {
    setup_uart = setup_uart,
    setup_uart_event = setup_uart_event,
}