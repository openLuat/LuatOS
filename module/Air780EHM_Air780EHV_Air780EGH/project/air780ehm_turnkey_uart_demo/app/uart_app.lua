--[[
@module  uart_app
@summary 串口应用模块，提供串口通信功能
@version 1.0.0
@date    2026.03.17
]]

local uart_app = {}

-- 串口配置表
local uart_config = {
    [1] = { id = 1, baudrate = 115200, databits = 8, stopbits = 1, parity = uart.PARITY_NONE },
    [2] = { id = 2, baudrate = 115200, databits = 8, stopbits = 1, parity = uart.PARITY_NONE },
    [3] = { id = 3, baudrate = 115200, databits = 8, stopbits = 1, parity = uart.PARITY_NONE },
}

-- 当前打开的串口
local current_uart_id = nil

-- 波特率选项
local baudrate_options = {2000000,921600,460800,230400,115200,57600,38400,19200,9600,4800,2400}

-- 打开串口
function uart_app.open(uart_id, baudrate_str)
    log.info("uart_app", "【打开串口】开始 - 串口ID:" .. tostring(uart_id) .. " 波特率:" .. tostring(baudrate_str))

    if current_uart_id then
        log.info("uart_app", "【打开串口】关闭已有串口:" .. tostring(current_uart_id))
        uart.close(current_uart_id)
        log.info("uart", "关闭串口", current_uart_id)
    end

    local baudrate = tonumber(baudrate_str) or 115200
    log.info("uart_app", "【打开串口】解析波特率: " .. baudrate)

    local config = uart_config[uart_id]

    if not config then
        log.error("uart_app", "【打开串口】错误 - 不支持的串口ID:" .. tostring(uart_id))
        log.error("uart", "不支持的串口", uart_id)
        return false
    end

    config.baudrate = baudrate
    log.info("uart_app", "【打开串口】配置参数 - ID:" .. config.id .. " 波特率:" .. config.baudrate ..
              " 数据位:" .. config.databits .. " 停止位:" .. config.stopbits .. " 校验位:" .. tostring(config.parity))

    log.info("uart_app", "【打开串口】调用uart.setup()...")
    local result = uart.setup(
        config.id,
        config.baudrate,
        config.databits,
        config.stopbits,
        config.parity
    )

    if result then
        current_uart_id = config.id
        log.info("uart_app", "【打开串口】成功 - 串口ID:" .. current_uart_id)
        log.info("uart", "打开串口", config.id, "波特率", config.baudrate)
        sys.publish("uart_opened", config.id, config.baudrate)
        return true
    else
        log.error("uart_app", "【打开串口】失败 - uart.setup()返回false")
        log.error("uart", "打开串口失败", config.id)
        return false
    end
end

-- 关闭串口
function uart_app.close()
    log.info("uart_app", "【关闭串口】开始")
    if current_uart_id then
        log.info("uart_app", "【关闭串口】关闭串口ID:" .. current_uart_id)
        uart.close(current_uart_id)
        log.info("uart", "关闭串口", current_uart_id)
        sys.publish("uart_closed", current_uart_id)
        current_uart_id = nil
        log.info("uart_app", "【关闭串口】成功")
        return true
    end
    log.warn("uart_app", "【关闭串口】没有打开的串口")
    return false
end

-- 发送数据
function uart_app.send(data)
    log.info("uart_app", "【发送数据】开始 - 数据长度:" .. (#data or 0))
    if not current_uart_id then
        log.error("uart_app", "【发送数据】错误 - 串口未打开")
        log.error("uart", "串口未打开")
        return false
    end

    log.info("uart_app", "【发送数据】调用uart.write()...")
    local sent = uart.write(current_uart_id, data)
    log.info("uart_app", "【发送数据】结果 - 实际发送:" .. sent .. "字节")
    log.info("uart", "发送", current_uart_id, "字节数", #data)
    sys.publish("uart_sent", current_uart_id, data)
    local success = (sent > 0)
    if not success then
        log.warn("uart_app", "【发送数据】警告 - 发送字节数为0")
    end
    return success
end

-- 发送十六进制数据
function uart_app.send_hex(hex_str)
    if not current_uart_id then
        log.error("uart", "串口未打开")
        return false
    end

    -- 将十六进制字符串转换为字节
    local data = hex_str:fromHex()
    if data then
        return uart_app.send(data)
    else
        log.error("uart", "十六进制转换失败")
        return false
    end
end

-- 串口接收任务
local function uart_receive_task()
    log.info("uart_app", "【接收任务】串口接收任务已启动")
    while true do
        if current_uart_id then
            local data = uart.read(current_uart_id, 1024)
            if data and #data > 0 then
                log.info("uart_app", "【接收任务】接收到数据 - 串口ID:" .. current_uart_id .. " 字节数:" .. #data)
                log.info("uart", "接收", current_uart_id, "字节数", #data, "数据", data)
                sys.publish("uart_data", current_uart_id, data)
            end
        end
        sys.wait(50) -- 轮询间隔
    end
end

-- 获取波特率选项
function uart_app.get_baudrate_options()
    return baudrate_options
end

-- 获取当前串口状态
function uart_app.get_status()
    return {
        is_open = current_uart_id ~= nil,
        uart_id = current_uart_id,
        baudrate = current_uart_id and uart_config[current_uart_id].baudrate or nil
    }
end

-- 启动接收任务
sys.taskInit(uart_receive_task)

log.info("uart_app", "【模块加载】串口应用模块加载完成")

return uart_app
