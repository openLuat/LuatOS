uart2_setup = {}
-- 设置UART2的函数
local function setup_uart2(baud_rate, data_bit, stop_bit, parity, bit_order, buff)

    local result2 = uart.setup(2, baud_rate, data_bit, stop_bit, parity, bit_order, buff)
    print(string.format(
        "uart2.setupuartid %d, 波特率 %d, 数据位 %d, 停止位 %s, 校验位 %s, 大小端 %s, 缓冲区大小 %d) = 设置结果 %d",
        2, baud_rate, data_bit, stop_bit, tostring(parity), tostring(bit_order), buff, result2))
    return result2
end

-- 注册UART2事件的函数

uart.on(2, "receive", function(id, len)
    local data = uart.read(id, len)
    log.info("uart2接收到的是", id, len, data)
    -- 将接收到的数据回写到uart3
    uart.write(2, data)
end)

return {
    setup_uart2 = setup_uart2
    -- setup_uart2_event = setup_uart2_event
}
