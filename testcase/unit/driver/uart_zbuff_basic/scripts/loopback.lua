PROJECT = "uart_loopback"
VERSION = "1.0.0"

local TEST_UART_SEND = 19
local TEST_UART_RECV = 18
local TEST_BAUD = 115200

sys.taskInit(function()
    log.info("uart_loopback", "===== UART Loopback Test =====")
    log.info("uart_loopback", "Send UART: COM" .. TEST_UART_SEND .. ", Recv UART: COM" .. TEST_UART_RECV)

    local result = uart.setup(TEST_UART_RECV, TEST_BAUD, 8, 1, uart.None, uart.LSB, 1024)
    if result ~= 0 then
        log.error("uart_loopback", "Failed to setup receiver UART, result=" .. tostring(result))
        os.exit(1)
    end
    log.info("uart_loopback", "Receiver UART setup OK")

    result = uart.setup(TEST_UART_SEND, TEST_BAUD, 8, 1, uart.None, uart.LSB, 1024)
    if result ~= 0 then
        log.error("uart_loopback", "Failed to setup sender UART, result=" .. tostring(result))
        os.exit(1)
    end
    log.info("uart_loopback", "Sender UART setup OK")

    local received_data = ""
    uart.on(TEST_UART_RECV, "receive", function(id, len)
        log.info("uart_loopback", "Receive callback, len=" .. tostring(len))
        local data = uart.read(TEST_UART_RECV, len)
        if data then
            received_data = received_data .. data
            log.info("uart_loopback", "Received: " .. tostring(#data) .. " bytes, total: " .. tostring(#received_data))
        end
    end)

    sys.wait(500)

    local test_data = "Hello UART Loopback Test! 0123456789"
    log.info("uart_loopback", "Sending " .. tostring(#test_data) .. " bytes")
    local sent = uart.write(TEST_UART_SEND, test_data)
    log.info("uart_loopback", "Sent " .. tostring(sent) .. " bytes")

    local wait_count = 0
    while #received_data == 0 and wait_count < 50 do
        sys.wait(100)
        wait_count = wait_count + 1
    end

    log.info("uart_loopback", "Expected: " .. tostring(#test_data) .. " bytes, Received: " .. tostring(#received_data))

    if received_data == test_data then
        log.info("uart_loopback", "===== TEST PASSED =====")
    else
        log.error("uart_loopback", "===== TEST FAILED =====")
    end

    uart.close(TEST_UART_SEND)
    uart.close(TEST_UART_RECV)
    os.exit(0)
end)

sys.run()
