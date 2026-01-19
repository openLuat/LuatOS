
local loopback = {}
local uart1 = require("uart1_setup")
local uart2 = require("uart2_setup")

-- 定义测试参数
local baud_rates = {2000000, 921600, 460800, 230400, 115200, 57600, 38400, 19200, 14400, 9600, 4800, 2400, 1200, 600}
-- local baud_rates = {2000000}
-- local data_bits = {7, 8}
local data_bits = {8} -- 8910系列只有8

-- local stop_bits = {0.5, 1, 1.5, 2}
local stop_bits = {1, 2} -- 8910系列只有1和2

local parities = {uart.None, uart.Even, uart.Odd}
local bit_orders = {uart.LSB, uart.MSB}
local buff_size = {256, 1024, 2048, 4096} -- 这里因为芯片差异 8101或者8000内部的wif芯片 不支持设缓冲区为1的情况，换成512就行

config_info = {}
local received = false
local function build_config_info(baud_rate, data_bit, stop_bit, parity, bit_order, buff)
    return string.format("波特率=%d, 数据位=%d, 停止位=%s, 校验位=%s, 大小端=%s, 缓冲区=%d",
        baud_rate, data_bit, stop_bit == 1 and "1" or "2",
        parity == uart.None and "None" or (parity == uart.Even and "Even" or "Odd"),
        bit_order == uart.LSB and "LSB" or "MSB", buff)
end

local function test_single_config(baud_rate, data_bit, stop_bit, parity, bit_order, buff, test_count)
    config_info = build_config_info(baud_rate, data_bit, stop_bit, parity, bit_order, buff)
    log.info(string.format("第%d项测试开始,当前配置为: %s", test_count, config_info))
     uart1.clean_uart1_status()
    -- 设置uart1
    local uart1_set_result = uart1.setup_uart1(baud_rate, data_bit, stop_bit, parity, bit_order, buff)
    -- 成功时返回0值
    assert(uart1_set_result == 0, string.format("UART1设置失败 [配置: %s]", config_info))
    
    -- 设置uart2
    local uart2_set_result = uart2.setup_uart2(baud_rate, data_bit, stop_bit, parity, bit_order, buff)
    -- 成功时返回0值
    assert(uart2_set_result == 0, string.format("UART2设置失败 [配置: %s]", config_info))
    
    -- 注册UART事件
    uart1.setup_uart1_event()
    uart2.setup_uart2_event()
    
    -- 测试数据发送
    local test_data = "Hello UART Loopback!\r\n"
    log.info("uart1发送数据" .. test_data .. "给uart2")
    local uart1_data = uart.write(1, test_data)
    
    -- 等待发送完成
    assert(uart1_data == #test_data, 
        string.format("UART1发送数据长度不匹配 [配置: %s] : 预期 %d, 实际 %d", 
            config_info, #test_data, uart1_data))
    
    --"等待回环数据（3秒超时）
    local wait_start = os.time()

    while os.time() - wait_start < 3 do
        -- 每500ms等待一次
        sys.waitUntil("UART1_RECEIVE_OK", 500)
        received = uart1.get_uart1_received()
        if received then
            log.info("已收到回环数据")
            break  -- 收到数据，跳出等待循环
        end
        
    end  
    -- 如果3秒内没有触发断言，说明可能：
    -- 1. 没接线，所以没收到数据
    -- 2. 回调函数有问题
    -- 3. 其他硬件问题
    assert(received == true, string.format("回环测试超时失败 [配置: %s] : 3秒内未收到回环数据,检查接线是否有误", config_info))
    -- -- 关闭UART
    uart.close(1)
    uart.close(2)

    sys.wait(50)
    log.info(string.format("✓ 第%d项测试通过 [配置: %s]", test_count, config_info))
end

-- 测试函数（循环测试，任何失败立即退出）
function loopback.test_uart_loopback()
    local test_count = 0

    log.info("===== UART回环测试开始 =====")
    log.info("注意：任何一次失败都将立即停止所有测试")

    for _, baud_rate in ipairs(baud_rates) do
        for _, data_bit in ipairs(data_bits) do
            for _, stop_bit in ipairs(stop_bits) do
                for _, parity in ipairs(parities) do
                    for _, bit_order in ipairs(bit_orders) do
                        for _, buff in ipairs(buff_size) do
                            test_count = test_count + 1

                            log.info(string.format("\n--- 开始第 %d 项测试 ---", test_count))
                            -- 执行测试，任何错误都会直接抛出
                            test_single_config(baud_rate, data_bit, stop_bit, parity, bit_order, buff, test_count)

                            log.info(string.format("--- 第 %d 项测试完成 ---", test_count))
                        end
                    end
                end
            end
        end
    end

    log.info("===== UART回环测试完成，所有测试通过 =====")
end

return loopback





