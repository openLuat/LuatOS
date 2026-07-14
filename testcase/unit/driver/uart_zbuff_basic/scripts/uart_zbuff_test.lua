local uart_zbuff_test = {}

local TEST_UART_ID = 18
local TEST_BAUD = 115200

local function setup_uart(uart_id, baud)
    local result = uart.setup(uart_id, baud, 8, 1, uart.None, uart.LSB, 1024)
    return result
end

local function test_uart_rx_size_returns_zero_when_no_data(uart_id)
    log.info("test", "test_uart_rx_size_returns_zero_when_no_data")
    local size = uart.rxSize(uart_id)
    assert(size == 0, "uart.rxSize should return 0 when no data, got " .. tostring(size))
    log.info("test", "  PASS: rxSize returns 0 when buffer empty")
end

local function test_uart_rx_returns_zero_when_no_data(uart_id)
    log.info("test", "test_uart_rx_returns_zero_when_no_data")
    local buff = zbuff.create(1024)
    local len = uart.rx(uart_id, buff)
    assert(len == 0, "uart.rx should return 0 when no data, got " .. tostring(len))
    log.info("test", "  PASS: rx returns 0 when buffer empty")
end

function uart_zbuff_test.test_uart_zbuff_mode_setup()
    log.info("test", "test_uart_zbuff_mode_setup")
    local result = setup_uart(TEST_UART_ID, TEST_BAUD)
    if result ~= 0 then
        log.info("test", "  SKIP: Cannot open UART port (result=" .. tostring(result) .. ") - no COM ports available")
        log.info("test", "  NOTE: Full test requires com0com or hardware ports")
        return
    end
    log.info("test", "  PASS: uart.setup succeeded")
    uart.close(TEST_UART_ID)
end

function uart_zbuff_test.test_uart_rx_size_query_mode()
    log.info("test", "test_uart_rx_size_query_mode")
    local result = setup_uart(TEST_UART_ID, TEST_BAUD)
    if result ~= 0 then
        log.info("test", "  SKIP: Cannot open UART port (result=" .. tostring(result) .. ")")
        return
    end
    test_uart_rx_size_returns_zero_when_no_data(TEST_UART_ID)
    uart.close(TEST_UART_ID)
end

function uart_zbuff_test.test_uart_rx_query_mode()
    log.info("test", "test_uart_rx_query_mode")
    local result = setup_uart(TEST_UART_ID, TEST_BAUD)
    if result ~= 0 then
        log.info("test", "  SKIP: Cannot open UART port (result=" .. tostring(result) .. ")")
        return
    end
    test_uart_rx_returns_zero_when_no_data(TEST_UART_ID)
    uart.close(TEST_UART_ID)
end

function uart_zbuff_test.test_uart_rx_clear()
    log.info("test", "test_uart_rx_clear")
    local result = setup_uart(TEST_UART_ID, TEST_BAUD)
    if result ~= 0 then
        log.info("test", "  SKIP: Cannot open UART port (result=" .. tostring(result) .. ")")
        return
    end
    local size_before = uart.rxSize(TEST_UART_ID)
    uart.rxClear(TEST_UART_ID)
    local size_after = uart.rxSize(TEST_UART_ID)
    assert(size_after == 0, "uart.rxClear should clear buffer, size_after=" .. tostring(size_after))
    log.info("test", "  PASS: rxClear works (size before=" .. tostring(size_before) .. " after=" .. tostring(size_after) .. ")")
    uart.close(TEST_UART_ID)
end

function uart_zbuff_test.test_uart_rx_zbuff_read()
    log.info("test", "test_uart_rx_zbuff_read")
    local result = setup_uart(TEST_UART_ID, TEST_BAUD)
    if result ~= 0 then
        log.info("test", "  SKIP: Cannot open UART port (result=" .. tostring(result) .. ")")
        return
    end
    local size = uart.rxSize(TEST_UART_ID)
    local buff = zbuff.create(1024)
    local len = uart.rx(TEST_UART_ID, buff)
    log.info("test", "  rxSize=" .. tostring(size) .. " rx len=" .. tostring(len))
    if size > 0 and len > 0 then
        assert(len == size, "rx should return size matching rxSize")
        assert(buff.used == len, "zbuff.used should match len")
        log.info("test", "  PASS: zbuff read worked correctly")
    else
        log.info("test", "  INFO: No data available (send data to serial port to test full loop)")
    end
    uart.close(TEST_UART_ID)
end

return uart_zbuff_test
