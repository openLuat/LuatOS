--[[
@module  app_lpuart
@summary UART功能应用模块
@version 1.0
@date    2026.02.12
@author  马梦阳
@usage
本模块负责低功耗UART应用，核心业务逻辑为：
1、初始化uart参数，设置波特率为9600，数据位8位，无校验位，1位停止位
2、配置uart发送与接收回调函数，用于处理发送完成和接收数据
3、对接收到的数据进行检测，当收到A0001指令时发布“CAMERA_TAKE_PHOTO_REQ”消息，通知拍照模块（例如app_camera.lua）执行拍照操作
4、拍照模块执行完拍照操作后，发布“CAMERA_TAKE_PHOTO_RSP”消息，携带操作结果和数据
5、收到“CAMERA_TAKE_PHOTO_RSP”消息后，根据操作结果和数据，判断是否需要将图像数据发送出去
6、需要将图像数据通过UART发送时，先关闭当前UART，重新设置波特率为115200，发送数据，发送完成后关闭UART，重新设置波特率为9600
]]


-- 使用UART1
local UART_ID = 1
-- 串口接收数据缓冲区
local read_buf = ""

-- false表示空闲，true表示正常处理拍照回传业务
local is_busy = false


-- 串口发送完成回调函数
local function uart_sent_callback()
    sys.publish("SEND_PHOTO_DONE")
end


-- 处理拍照结果响应消息任务
local function camera_take_photo_rsp_task(data)
    log.info("camera_take_photo_rsp_task", type(data), data:used())

    local uart_tx_start = 0     -- 已发送数据的起始位置
    local uart_tx_len = 102400  -- 每次发送的数据长度

    uart.close(UART_ID)
    uart.setup(UART_ID, 115200, 8, 1)

    -- 循环发送数据，直到所有数据都发送完成
    while true do
        if data:used() - uart_tx_start >= 102400 then
            uart_tx_len = 102400
        elseif data:used() - uart_tx_start < 102400 then
            uart_tx_len = data:used() - uart_tx_start
        elseif data:used() - uart_tx_start == 0 then
            break
        end

        uart.tx(UART_ID, data, uart_tx_start, uart_tx_len)

        uart_tx_start = uart_tx_start + uart_tx_len

        -- 等待发送完成（最多等待30秒）
        local result = sys.waitUntil("SEND_PHOTO_DONE", 30 * 1000)
        if not result then
            log.error("uart.tx timeout")
            break
        end
    end

    uart.close(UART_ID)
    uart.setup(UART_ID, 9600, 8, 1)

    is_busy = false
end


-- 发布拍照结果响应消息
local function camera_take_photo_rsp(result, data)
    if result then
        log.info("camera_take_photo_rsp", result, type(data), data:used(), is_busy)
        sys.taskInit(camera_take_photo_rsp_task, data)
    else
        log.info("camera_take_photo_rsp", result)
        is_busy = false
    end
end


-- 处理串口缓冲区数据超时函数
-- 防止将一大包数据拆分成多个小包来处理
local function concat_timeout_func()
    log.info("concat_timeout_func", read_buf:len(), is_busy)

    -- 如果存在尚未处理的串口缓冲区数据；
    -- 将数据通过publish通知其他应用功能模块处理；
    -- 然后清空本文件的串口缓冲区数据
    if read_buf:len() > 0 then
        if not is_busy then
            -- 检查是否包含拍照指令
            if read_buf:find("A0001") then
                sys.publish("CAMERA_TAKE_PHOTO_REQ")
                is_busy = true
            end
        end
        read_buf = ""
    end
end


-- UART1的数据接收中断处理函数，UART1接收到数据时，会执行此函数
local function read()
    local s
    while true do
        -- 非阻塞读取UART1接收到的数据，最长读取1024字节
        s = uart.read(UART_ID, 1024)

        -- 如果从串口没有读到数据
        if not s or s:len() == 0 then
            -- 启动50毫秒的定时器，如果50毫秒内没收到新的数据，则处理当前收到的所有数据
            -- 这样处理是为了防止将一大包数据拆分成多个小包来处理
            -- 例如pc端串口工具下发1100字节的数据，可能会产生将近20次的中断进入到read函数，才能读取完整
            -- 此处的50毫秒可以根据自己项目的需求做适当修改，在满足整包拼接完整的前提下，时间越短，处理越及时
            sys.timerStart(concat_timeout_func, 50)
            -- 跳出循环，退出本函数
            break
        end

        log.info("uart_app.read len", s:len())
        -- log.info("uart_app.read", s)

        -- 将本次从串口读到的数据拼接到串口缓冲区read_buf中
        read_buf = read_buf..s
    end
end



-- 初始化UART1，波特率115200，数据位8，停止位1
uart.setup(UART_ID, 9600, 8, 1)

-- 注册UART1的数据接收中断处理函数，UART1接收到数据时，会执行read函数
uart.on(UART_ID, "receive", read)

-- 注册串口发送回调
uart.on(UART_ID, "sent", uart_sent_callback)

-- 订阅拍照结果响应消息
sys.subscribe("CAMERA_TAKE_PHOTO_RSP", camera_take_photo_rsp)
