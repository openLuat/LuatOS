uart3_setup = {}

-- 设置uart3的函数
local function setup_uart3(baud_rate, data_bit, stop_bit, parity, bit_order, buff)
    -- --  每次设置前先关闭uart一次
    -- uart.close(3)
    local result1 = uart.setup(3, baud_rate, data_bit, stop_bit, parity, bit_order, buff)
    print(string.format(
        "uart3.setup(uartid %d, 波特率 %d, 数据位 %d, 停止位 %s, 校验位 %s, 大小端 %s, 缓冲区大小 %d) = 设置结果%d",
        3, baud_rate, data_bit, stop_bit, tostring(parity), tostring(bit_order), buff, result1))
    return result1
end

local test_data = "Hello UART Loopback!\r\n"

-- 注册uart3事件的函数
uart.on(3, "receive", function(id, len)
    local received_data = uart.read(id, len)
    print("uart3接收到的是", received_data)
    if received_data == test_data then
        print("回环的数据没有问题")
    else
        print("回环的数据有问题应该是 " .. test_data .. ", 结果是: " .. received_data)
    end
end)

return {
    setup_uart3 = setup_uart3
}
