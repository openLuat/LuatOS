local loopback = {}

-- 直接引入UART模块
local uart_first = require("uart_setup_first")
local uart_second = require("uart_setup_second")

-- 获取模块型号
local platform = rtos.bsp()
log.info("当前模块型号:", platform)

-- 根据模块型号定义UART配对
local uart_pairs = {}

if platform == "Air8000" then
    -- Air8000引脚配置
    pins.setup(17, "UART1_RXD")
    pins.setup(16, "UART1_TXD")
    pins.setup(41, "UART2_RXD")
    pins.setup(40, "UART2_TXD")
    pins.setup(48, "UART11_RX")
    pins.setup(49, "UART11_TX")
    pins.setup(60, "UART12_TX")
    pins.setup(59, "UART12_RX")

    -- Air8000: 测试两组UART配对
    uart_pairs = {
        {
            name = "UART1-UART2",
            first = {id = 1, module = uart_first},
            second = {id = 2, module = uart_second},
            test_data = "Hello UART Loopback!\r\n"
        },
        {
            name = "UART11-UART12",
            first = {id = 11, module = uart_first},
            second = {id = 12, module = uart_second},
            test_data = "Hello UART11-UART12 Loopback!\r\n"
        }
    }
elseif platform == "Air8101" then
    -- Air8101引脚配置
    pins.setup(12, "UART1_TX")
    pins.setup(11, "UART1_RX")
    pins.setup(3, "UART2_RX")
    pins.setup(73, "UART2_TX")

    -- Air8101: 测试uart1和uart2
    uart_pairs = {
        {
            name = "UART1-UART2",
            first = {id = 1, module = uart_first},
            second = {id = 2, module = uart_second},
            test_data = "Hello UART1-UART2 Loopback!\r\n"
        }
    }
elseif platform == "Air780EPM" or platform == "Air780EHM" or platform == "Air780EHV" then
    -- 718系列引脚配置
    pins.setup(17, "UART1_RXD")
    pins.setup(18, "UART1_TXD")
    pins.setup(28, "UART2_RXD")
    pins.setup(29, "UART2_TXD")

    -- 718: 测试UART1-UART2配对
    uart_pairs = {
        {
            name = "UART1-UART2",
            first = {id = 1, module = uart_first},
            second = {id = 2, module = uart_second},
            test_data = "Hello UART Loopback!\r\n"
        }
    }
else
    log.info("当前模块暂未适配:", platform)
    uart_pairs = {}
end

-- 定义测试参数
local baud_rates = {2000000, 921600, 460800, 230400, 115200, 57600, 38400, 19200, 14400, 9600, 4800, 2400, 1200, 600}
local data_bits = {8}
local stop_bits = {1, 2}
local parities = {uart.None, uart.Even, uart.Odd}
local bit_orders = {uart.LSB, uart.MSB}
local buff_size = {256, 1024, 2048, 4096}

local function build_config_info(baud_rate, data_bit, stop_bit, parity, bit_order, buff)
    return string.format("波特率=%d, 数据位=%d, 停止位=%s, 校验位=%s, 大小端=%s, 缓冲区=%d",
        baud_rate, data_bit, stop_bit == 1 and "1" or "2",
        parity == uart.None and "None" or (parity == uart.Even and "Even" or "Odd"),
        bit_order == uart.LSB and "LSB" or "MSB", buff)
end

local function test_single_config(uart_pair, baud_rate, data_bit, stop_bit, parity, bit_order, buff, test_count)
    local pair_name = uart_pair.name
    local first_uart = uart_pair.first
    local second_uart = uart_pair.second
    local test_data = uart_pair.test_data

    config_info = build_config_info(baud_rate, data_bit, stop_bit, parity, bit_order, buff)
    log.info(string.format("第%d项测试开始 [配对:%s] 配置: %s", test_count, pair_name, config_info))

    -- 清理状态
    first_uart.module.clean_uart_status()

    -- 设置第一个UART
    local first_set_result = first_uart.module.setup_uart(first_uart.id, baud_rate, data_bit, stop_bit, parity, bit_order, buff)
    assert(first_set_result == 0, string.format("UART%d设置失败 [配对:%s] [配置: %s]", first_uart.id, pair_name, config_info))

    -- 设置第二个UART
    local second_set_result = second_uart.module.setup_uart(second_uart.id, baud_rate, data_bit, stop_bit, parity, bit_order, buff)
    assert(second_set_result == 0, string.format("UART%d设置失败 [配对:%s] [配置: %s]", second_uart.id, pair_name, config_info))

    -- 注册UART事件，传入测试数据
    first_uart.module.setup_uart_event(test_data)
    second_uart.module.setup_uart_event(test_data)

    -- 测试数据发送
    log.info(string.format("UART%d发送数据给UART%d: %s", first_uart.id, second_uart.id, test_data))
    local uart_first_data = uart.write(first_uart.id, test_data)

    -- 等待发送完成
    assert(uart_first_data == #test_data,
        string.format("UART%d发送数据长度不匹配 [配对:%s] [配置: %s] : 预期 %d, 实际 %d",
            first_uart.id, pair_name, config_info, #test_data, uart_first_data))

    -- 等待回环数据（3秒超时）
    local wait_start = os.time()
    local received = false

    while os.time() - wait_start < 3 do
        sys.waitUntil("UART_RECEIVE_OK_" .. first_uart.id, 500)
        received = first_uart.module.get_uart_received()
        if received then
            log.info(string.format("已收到回环数据 [配对:%s]", pair_name))
            break
        end
    end

    assert(received == true, string.format(
        "回环测试超时失败 [配对:%s] [配置: %s] : 3秒内未收到回环数据,检查接线是否有误",
        pair_name, config_info))

    -- 关闭UART
    uart.close(first_uart.id)
    uart.close(second_uart.id)

    sys.wait(50)
    log.info(string.format("✓ 第%d项测试通过 [配对:%s] [配置: %s]", test_count, pair_name, config_info))
end

-- 测试函数（循环测试，任何失败立即退出）
function loopback.test_uart_loopback()
    if #uart_pairs == 0 then
        log.error("没有可用的UART配对配置，请检查模块型号:", platform)
        return
    end
    
    local test_count = 0

    log.info("===== UART回环测试开始 =====")
    log.info("模块型号:", platform)
    log.info("测试配对数量:", #uart_pairs)
    for _, pair in ipairs(uart_pairs) do
        log.info("  -", pair.name, "UART" .. pair.first.id .. " <-> UART" .. pair.second.id)
    end
    log.info("注意：任何一次失败都将立即停止所有测试")

    for pair_index, uart_pair in ipairs(uart_pairs) do
        log.info(string.format("\n========== 开始测试配对 %d/%d: %s ==========", pair_index, #uart_pairs, uart_pair.name))

        for _, baud_rate in ipairs(baud_rates) do
            for _, data_bit in ipairs(data_bits) do
                for _, stop_bit in ipairs(stop_bits) do
                    for _, parity in ipairs(parities) do
                        for _, bit_order in ipairs(bit_orders) do
                            for _, buff in ipairs(buff_size) do
                                test_count = test_count + 1
                                log.info(string.format("\n--- 开始第 %d 项测试 [%s] ---", test_count, uart_pair.name))
                                test_single_config(uart_pair, baud_rate, data_bit, stop_bit, parity, bit_order, buff, test_count)
                                log.info(string.format("--- 第 %d 项测试完成 [%s] ---", test_count, uart_pair.name))
                            end
                        end
                    end
                end
            end
        end
        
        log.info(string.format("\n========== 完成测试配对: %s ==========\n", uart_pair.name))
    end

    log.info("===== UART回环测试完成，所有测试通过 =====")
end

return loopback