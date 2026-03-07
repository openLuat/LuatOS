local uart3 = require("uart3_setup")
local uart2 = require("uart2_setup")

-- 定义测试参数
local baud_rates = {2000000, 921600, 460800, 230400, 115200, 57600, 38400, 19200, 9600, 4800, 2400, 1200,600,300,200,100,1}
local data_bits = {7, 8}
local stop_bits = {0.5, 1, 1.5, 2}
local parities = {uart.None, uart.Even, uart.Odd}
local bit_orders = {uart.LSB, uart.MSB}
local buff_size = { 1024, 2048, 4096}

-- 测试函数
local function test_uart_loopback()
    for _, baud_rate in ipairs(baud_rates) do
        for _, data_bit in ipairs(data_bits) do
            for _, stop_bit in ipairs(stop_bits) do
                for _, parity in ipairs(parities) do
                    for _, bit_order in ipairs(bit_orders) do
                        for _, buff in ipairs(buff_size) do
                            -- 设置uart3
                            local result1 = uart3.setup_uart3(baud_rate, data_bit, stop_bit, parity, bit_order, buff)
                            -- 设置UART2
                            local result2 = uart2.setup_uart2(baud_rate, data_bit, stop_bit, parity, bit_order, buff)
                            -- 注册UART事件
                            -- uart3.setup_uart3_event()
                            -- uart2.setup_uart2_event()
                            -- 测试数据发送
                            local test_data = "Hello UART Loopback!\r\n"
                            log.info("uart3发送数据" .. test_data .. "给uart2",uart.write(3, test_data))
                            
                            -- 等待一段时间，确保接收数据 
                            sys.wait(1000)
                        end
                    end
                end
            end
        end
    end
    print("All tests complete.")
end

-- 执行测试
sys.taskInit(test_uart_loopback)

