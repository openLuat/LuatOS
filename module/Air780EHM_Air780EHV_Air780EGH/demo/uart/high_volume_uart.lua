--[[
@module  high_volume_uart
@summary 串口大数据收发功能模块
@version 1.0
@date    2025.09.23
@author  魏健强
@usage
本demo演示的核心功能为：
1.开启串口，配置波特率等参数；
2.设置接收回调函数
3.定时向串口发送数据
4.使用zbuff的方式收发数据
]] 
local uartid = 1 -- 根据实际设备选取不同的uartid

uart_mode_zbuff = true -- 是否使用zbuff方式收发数据
local sendres = 0 -- 发送结果标志位
local function uart_send_cb(id)
    sendres = 1 -- 标志位置1，表示发送完成
    log.info("uart", id, "数据发送完成回调")
end

if uart_mode_zbuff then
    local rxbuff = zbuff.create(10240) -- 接收数据的zbuff
    local txbuff = zbuff.create(300000, 0x01) -- 发送数据的zbuff
    txbuff:seek(299999) -- 设置txbuff数据长度
    log.info("uart", "txbuff used", txbuff:used()) -- 查看txbuff已用长度
    local function uart_send()
        local tx_start = 0 -- 发送数据起始位置
        local tx_lenmax = 102400 -- 每次最大发送数据长度
        -- 判断已发送数据长度
        while true do
            local tx_len = tx_lenmax
            -- 发送数据
            sendres = 0 -- 发送结果标志位置0，表示正在发送
            if txbuff:used() - tx_start <= tx_lenmax then -- 剩余数据长度小于每次最大发送长度
                tx_len = txbuff:used() - tx_start -- 计算本次发送数据长度
            end
            log.info("uart", "开始发送数据", "tx_start", tx_start, "tx_len", tx_len)
            uart.tx(uartid, txbuff, tx_start, tx_len)
            while sendres == 0 do -- 等待发送完成
                sys.wait(100)
            end
            tx_start = tx_start + tx_len -- 更新发送起始位置
            if tx_start >= txbuff:used() then
                break
            end
            log.info("uart", "数据发送调用完成")
        end
    end

    local function uart_cb(id, len)  -- 串口接收数据回调函数
        while 1 do
            log.info("uart", "缓冲区", uart.rxSize(id))
            local len = uart.rx(id, rxbuff)
            if len <= 0 then
                break
            end
            log.info("uart", "receive", id, rxbuff:used(), rxbuff:toStr())
            rxbuff:seek(0)
        end
    end

    -- 初始化
    uart.setup(uartid, -- 串口id
    115200, -- 波特率
    8, -- 数据位
    1, -- 停止位
    uart.NONE, -- 校验位，可选 uart.None/uart.Even/uart.Odd。默认 uart.None 无校验
    uart.LSB, -- 大小端，默认小端 uart.LSB, 可选 uart.MSB
    10240 -- 缓冲区大小，默认值1024，接收大数据时需要根据数据大小增大缓冲区
    )

    -- 收取数据会触发回调, 这里的"receive" 是固定值
    uart.on(uartid, "receive", uart_cb)

    -- 发送数据完成会触发回调, 这里的"sent" 是固定值
    uart.on(uartid, "sent", uart_send_cb)

    sys.taskInit(uart_send)
else
    local function uart_send()
        -- 循环两秒向串口发一次数据
        while true do
            sys.wait(2000)
            uart.write(uartid, "test data.")
        end
    end

    local function uart_cb(id, len)
        local s = ""
        repeat
            s = uart.read(id, 10240) -- 一次性读出所有缓冲区中的数据，避免分包
            if #s > 0 then -- #s 是取字符串的长度
                -- 关于收发hex值,请查阅 https://doc.openluat.com/article/583
                log.info("uart", "receive", id, #s, s)
                -- log.info("uart", "receive", id, #s, s:toHex()) --如果传输二进制/十六进制数据, 部分字符不可见, 不代表没收到
            end
        until s == ""
    end

    -- 初始化
    uart.setup(uartid, -- 串口id
    115200, -- 波特率
    8, -- 数据位
    1, -- 停止位
    uart.NONE, -- 校验位，可选 uart.None/uart.Even/uart.Odd。默认 uart.None 无校验
    uart.LSB, -- 大小端，默认小端 uart.LSB, 可选 uart.MSB
    10240 -- 缓冲区大小，默认值1024，接收大数据时需要根据数据大小增大缓冲区
    )

    -- 收取数据会触发回调, 这里的"receive" 是固定值
    uart.on(uartid, "receive", uart_cb)

    -- 发送数据完成会触发回调, 这里的"sent" 是固定值
    uart.on(uartid, "sent", uart_send_cb)

    sys.taskInit(uart_send)

end

