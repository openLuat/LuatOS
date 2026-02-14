-- TCP回环测试模块
local tcp_tests = {}
local libnet = require "libnet"
local taskName = "TCP_ECHO_TASK"
local netCB = nil
local protocol = false
local ssl = false

-- TCP回环测试函数
--40次复杂数据回环，每次数据都不完全一致。
function tcp_tests.test_tcp_echo()
    local ip = "airtest.openluat.com"
    local port = 2901
    local test_count = 40 -- 总发送次数
    local interval = 3000 -- 间隔时间
    local recive_count = 0 -- 接收计数

    log.info("tcp_echo", "=== TCP Echo Test Started ===")
    log.info("tcp_echo", string.format("Server: %s:%d", ip, port))
    log.info("tcp_echo", string.format("Test count per cycle: %d", test_count))
    log.info("tcp_echo", string.format("Test interval: %dms", interval))

    -- 创建发送和接收数据缓冲区
    -- 1.创建发送数据缓冲区
    local send_buff = zbuff.create(1024)
    assert(send_buff ~= nil, "发送数据缓冲区创建失败！")
    -- 2.创建接收数据缓冲区
    local recv_buff = zbuff.create(1024)
    assert(recv_buff ~= nil, "接收数据缓冲区创建失败！")

    -- 创建socket对象
    netCB = socket.create(nil, taskName)
    assert(netCB ~= nil, " 创建socket对象失败!")

    -- 打开network的debug日志信息
    local success, err = pcall(function()
        socket.debug(netCB, true)
    end)
    assert(success == true, "debug日志信息打开失败，错误原因是：", err)

    -- 配置socket对象的参数
    local config_result = socket.config(netCB, nil, protocol, ssl)
    assert(type(config_result) == "boolean", "socket.config返回的数据类型错误")
    assert(config_result == true, "配置socket对象的参数失败")


    -- 客户端连接服务器 (超时时间为30S)
    local connect_result = libnet.connect(taskName, 30000, netCB, ip, port)
    assert(type(connect_result) == "boolean", "socket.connect返回的数据类型错误,实际是%s:",
        type(connect_result))
    assert(connect_result == true, "客户端连接服务器失败")

    log.info("tcp_echo", "✓ TCP服务器连接成功!")
    -- 服务器连接和配置完成，后续将进行数据回环

    while recive_count < test_count do
        -- 每次循环都重新获取当前时间，确保每次发送的数据不同
        local current_time = os.time()
        local date_table = os.date("*t", current_time)

        -- 更复杂的数据格式
        -- 格式: JSON-like 字符串，包含多种数据类型
        local test_str = string.format(
            '{"seq":%d,"time":%d,"date":"%04d-%02d-%02d %02d:%02d:%02d","data":"test_message_%d","hex":0x%X,"random":%d}',
            recive_count + 1, -- 序列号
            current_time, -- 时间戳
            date_table.year, date_table.month, date_table.day, -- 日期
            date_table.hour, date_table.min, date_table.sec, -- 时间
            recive_count + 1, -- 消息序号
            math.random(0, 65535), -- 随机十六进制数
            math.random(1000, 9999) -- 随机数
        )
        
        log.info("tcp_echo", string.format("第%d次发送数据: %s", recive_count + 1, test_str))

        -- 清空发送缓冲区并写入新数据
        send_buff:write(test_str)
        assert(send_buff:used() > 0, "数据写入失败！")

        local succ, full = libnet.tx(taskName, 0, netCB, send_buff)
        assert(type(succ) == "boolean" and type(full) == "boolean", string.format(
            "libnet.tx()返回的数据类型错误，应为boolean,实际：第一个数据类型 %s为,第二个数据类型%s为：",
            type(succ), type(full)))
        assert(succ == true, string.format("数据发送失败，当前有效数据长度是: %d", send_buff:used()))

        assert(full == false, "发送缓冲区已满")

        -- 从发送缓冲区读取数据用于后续比较
        local send_data = send_buff:query()
        assert(send_data ~= nil, "读取缓冲区数据失败")
        send_buff:del()

        -- 等待接收事件，超时5秒
        local wait_result, event_param = libnet.wait(taskName, 5000, netCB)
        assert(wait_result == true, "等待数据接收超时或失败！")

        -- 接收数据
        local succ, param, _, _ = socket.rx(netCB, recv_buff)
        assert(succ == true, "数据接收失败")
        assert(param ~= 0, "接收到的数据长度为0")
        assert(recv_buff:used() > 0, "接收缓冲区的有效数据长度异常")

        -- 从接收缓冲区读取数据
        local recive_data = recv_buff:query()
        assert(recive_data ~= nil, "读取缓冲区数据失败")
        recv_buff:del()

        recive_count = recive_count + 1

        assert(recive_data == send_data,
            string.format("第%d次回环数据不匹配!\n发送数据长度(%d): %s\n接收数据长度(%d): %s",
                recive_count, #send_data, send_data, #recive_data, recive_data))

        log.info("tcp_echo", string.format("✓ 第%d次回环成功", recive_count))
        log.info("tcp_echo", string.format("发送数据: %s", send_data))
        log.info("tcp_echo", string.format("接收数据: %s", recive_data))
        log.info("tcp_echo", "----------------------------------------")

        -- 如果不是最后一次测试，等待指定间隔
        if recive_count < test_count then
            sys.wait(interval)
        end
    end

    -- 完成30次测试，主动断开连接
    log.info("tcp_echo",
        string.format("✓✓✓ 完成%d次回环测试，所有数据一致，断开连接...", test_count))
    local close_success, close_err = pcall(function()
        socket.close(netCB)
    end)
    assert(close_success == true, "断开连接失败!失败原因是：" .. tostring(close_err))

    log.info("tcp_echo", "✓ 连接已成功关闭!")

    -- 清理缓冲区
    send_buff:clear()
    recv_buff:clear()

    -- 最终结果
    log.info("tcp_echo", "================回环测试完成========================")
    assert(recive_count == 40, "接收成功次数不足40次")
    assert(recive_count == test_count, "发送成功和接收成功次数不一致")
    log.info("tcp_echo", "========================================")

    -- 等待3秒后程序结束
    log.info("tcp_echo", "等待3秒后退出...")
    sys.wait(3000)

end

return tcp_tests

