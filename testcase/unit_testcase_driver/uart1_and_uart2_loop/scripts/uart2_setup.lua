-- -- uart2_setup.lua
local function setup_uart2(baud_rate, data_bit, stop_bit, parity, bit_order, buff)
    local result2 = uart.setup(2, baud_rate, data_bit, stop_bit, parity, bit_order, buff)
    print(string.format(
        "uart2.setup(uartid %d, 波特率 %d, 数据位 %d, 停止位 %s, 校验位 %s, 大小端 %s, 缓冲区大小 %d) = 设置结果 %d",
        2, baud_rate, data_bit, stop_bit, tostring(parity), tostring(bit_order), buff, result2))
    return result2
end

local expected_data = "Hello UART Loopback!\r\n"
-- 注册UART2事件的函数（有完整的读取逻辑）
local function setup_uart2_event()
    uart.on(2, "receive", function(id, len)
        -- 第一次读取
        local data = uart.read(id, len)
        log.info("uart2接收到的数据", id, len, data)
        -- 检查缓冲区是否还有剩余数据
        local size = uart.rxSize(id)
        if size == 0 then
            assert(data == expected_data,
                string.format("uart2接收数据失败 [配置: %s] : 预期 '%s'(%d字节), 实际 '%s'(%d字节)",
                    config_info, expected_data, #expected_data, data, #data))
        else
                    log.info("uart2接收后缓冲区剩余", size, "字节")
            local all_data = data
            local total_len = len
            -- 如果缓冲区还有数据，继续读取
            while size > 0 do
                local more_data = uart.read(id, size)
                log.info("uart2继续读取", size, "字节:", more_data)

                if more_data then
                    all_data = all_data .. more_data
                    total_len = total_len + #more_data
                end
                -- 再次检查缓冲区
                size = uart.rxSize(id)
                log.info("uart2缓冲区剩余", size, "字节")
            end

            -- uart2数据接收断言
            assert(all_data == expected_data,
                string.format("uart2接收数据失败 [配置: %s] : 预期 '%s'(%d字节), 实际 '%s'(%d字节)",
                    config_info, expected_data, #expected_data, all_data, total_len))
        end
        -- 将接收到的数据回写到uart1
        local uart2_data = uart.write(2, expected_data)
        log.info("再将uart2收到的数据还回去", uart2_data)

        -- uart发送数据断言
        assert(uart2_data == #expected_data, string.format(
            "uart2发送数据失败 [配置: %s] : 预期 %d, 实际 %d", config_info, #expected_data, uart2_data))
    end)
end

return {
    setup_uart2 = setup_uart2,
    setup_uart2_event = setup_uart2_event
}

