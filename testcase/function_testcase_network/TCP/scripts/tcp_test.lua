-- TCP回环测试模块
local tcp_tests = {}
local libnet = require "libnet"
local taskName = "TCP_ECHO_TASK"
local netCB = nil
local protocol = false
local ssl = false
local ip = "airtest.openluat.com"
local port = 2901
local rtos_bsp = rtos.bsp()
local wifi_module = {"Air8000", "Air8101"} -- 支持wifi的模块

-- 查看网卡的联网状态(正常情况)
function tcp_tests.test_get_socket_adapter()
    local is_wifi_module = false
    local is_ready
    for _, model in ipairs(wifi_module) do
        if rtos_bsp == model then
            is_wifi_module = true
            break
        end
    end
    -- 支持wifi的模块用socket.LWIP_STA
    if is_wifi_module == true then
        is_ready, _ = socket.adapter(socket.LWIP_STA)
    else
        -- 支持4G的模块用socket.LWIP_GP
        is_ready, _ = socket.adapter(socket.LWIP_GP)
    end
    assert(is_ready == true, "网卡的网络未就绪！")

end

-- 默认使用wifi网卡连接，失败后使用默认网卡
function tcp_tests.test_get_socket_adapter_error()
    -- 1.默认使用socket.LWIP_STA网卡
    local is_ready, _ = socket.adapter(socket.LWIP_STA)
    if is_ready ~= true then
        -- 失败使用默认网关
        local is_ready1, _ = socket.adapter(socket.dft())
        assert(is_ready1 == true, "网卡的网络未就绪！")
    else
        assert(is_ready == true, "网卡的网络未就绪！")
    end
end

-- 使用默认网关进行配置
-- 联网成功后
-- 获取某个网卡上的本地 ip地址、网络掩码和网关地址；
-- adapter_id：1-14

function tcp_tests.test_get_socket_localIP()
    local adapter_id, last_reg_adapter_id = socket.dft()
    local dft_adapter = false
    if adapter_id >= 1 and adapter_id <= 14 then
        dft_adapter = true
    end
    log.info("adapter_id", adapter_id, dft_adapter)

    -- 查询默认网卡是否在定义的网络适配器范围内
    assert(dft_adapter == true, "默认网卡不在定义的网络适配器范围内！")

    -- 查看网卡的联网状态
    local is_ready, _ = socket.adapter(adapter_id)
    assert(is_ready == true, "网卡的网络未就绪！")

    -- 获取网卡上的本地 ip地址、网络掩码和网关地址；
    local ip, netmask, gatewa = socket.localIP(adapter_id)

    -- 联网成功后
    -- 返回值类型判断
    assert(type(ip) == "string", "socket.localIP()第一个返回值类型错误！")
    assert(type(netmask) == "string", "socket.localIP()第二个返回值类型错误！")
    assert(type(gatewa) == "string", "socket.localIP()第三个返回值类型错误！")

    -- 返回值不为空
    assert(ip ~= nil, "socket.localIP()第一个返回值为空！")
    assert(netmask ~= nil, "socket.localIP()第二个返回值为空！")
    assert(gatewa ~= nil, "socket.localIP()第三个返回值为空！")
end

-- 网卡未就绪情况下的参数

function tcp_tests.test_get_socket_localIP_error()

    -- 查看网卡的联网状态
    local is_ready, _ = socket.adapter(15)
    assert(is_ready == false, "网卡的网络就绪！")

    -- 获取网卡上的本地 ip地址、网络掩码和网关地址；
    local ip, netmask, gatewa = socket.localIP(15)

    -- 网络未就绪，返回值为空
    assert(ip == nil, "socket.localIP()第一个返回值应为空！")
    assert(netmask == nil, "socket.localIP()第二个返回值应为空！")
    assert(gatewa == nil, "socket.localIP()第三个返回值应为空！")
end

function tcp_tests.test_get_socket_sslLog_error()

    local success, err = pcall(function()
        socket.sslLog(-1)
    end)
    assert(success == true, "设置内核固件中ssl功能的log等级失败，原因是", err)
end

-- adapter_id：1-14(正确范围)

function tcp_tests.test_get_socket_create_error()

    netCB = socket.create(15, taskName)
    assert(netCB == nil, " 创建socket对象异常!")
end



function tcp_tests.test_get_socket_state_error()

    netCB = socket.create(15, taskName)
    assert(netCB == nil, " 创建socket对象异常!")
    -- 获取 socket 当前状态；
    local state, str = socket.state(netCB)

    -- 第一个返回值
    assert(state == nil ,"socket.state()第一个返回值应为空！")

    -- 第二个返回值
    assert(str == nil, "socket.state()第二个返回值应为空！")

end



function tcp_tests.test_get_socket_debug_error()

    netCB = socket.create(15, taskName)
    assert(netCB == nil, " 创建socket对象异常!")
    -- 获取 socket 当前状态；
       local success, err = pcall(function()
        socket.debug(netCB, true)
    end)
    assert(success == true, "debug日志信息打开失败，错误原因是：", err)

end



-- TCP回环测试函数
-- 40次复杂数据回环，每次数据都不完全一致。
function tcp_tests.test_tcp_echo()

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

    --查询默认网卡
    local adapter_id, last_reg_adapter_id = socket.dft()
    local dft_adapter = false
    if adapter_id >= 1 and adapter_id <= 14 then
        dft_adapter = true
    end
    log.info("adapter_id", adapter_id, dft_adapter)

    -- 查询默认网卡是否在定义的网络适配器范围内
    assert(dft_adapter == true, "默认网卡不在定义的网络适配器范围内！")

    -- 创建socket对象
    netCB = socket.create(adapter_id, taskName)
    assert(netCB ~= nil, " 创建socket对象失败!")

    --获取 socket 当前状态；
    local state, str = socket.state(netCB)
    --返回值类型判断
    assert(type(state) == "number", "socket.state()第一个返回值类型错误！")
    assert(type(str) == "string", "socket.state()第二个返回值类型错误！")

    --第一个返回值
    assert(state >= 0 and state <= 8, "socket.state()第一个返回值不在指定范围内！")

    --第二个返回值
    assert(str ~= nil, "socket.state()第二个返回值不为空！")

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

