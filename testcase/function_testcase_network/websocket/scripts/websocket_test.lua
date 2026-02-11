local websocket_tests = {}

-- 测试1: WebSocket客户端创建测试
-- WebSocket 客户端创建 :adapter类型为number.此处非8101选用socket.LWIP_GP，8101选用socket.LWIP_STA
function websocket_tests.test_WebsocketCreate_adapterNumber()
    local adapter
    if rtos.bsp() == "Air8101" then
        adapter = socket.LWIP_STA
    else
        adapter = socket.LWIP_GP
    end
    local wsc = websocket.create(adapter, "ws://echo.airtun.air32.cn/ws/echo")
    assert(wsc ~= nil, "WebSocket 客户端创建失败了")
    assert(type(wsc) == "userdata", string.format("返回值类型应该为userdata,实际是%s:", type(wsc)))
    -- 创建成功就关闭，避免资源泄露
    wsc:close()
end

-- WebSocket 客户端创建 :adapter为nil
function websocket_tests.test_WebsocketCreate_adapterNil()
    local wsc = websocket.create(nil, "ws://echo.airtun.air32.cn/ws/echo")
    assert(wsc ~= nil, "WebSocket 客户端创建失败了")
    assert(type(wsc) == "userdata", string.format("返回值类型应该为userdata,实际是%s:", type(wsc)))
    -- 创建成功就关闭，避免资源泄露
    wsc:close()

end

-- WebSocket 客户端创建异常测试:无效url，应创建失败
function websocket_tests.test_WebsocketCreateNilUrl()
    local success, err = pcall(function()
        websocket.create(nil, nil)
    end)
    assert(success == false, "无效url进行WebSocket客户端创建异常，应该失败，异常原因是", err)
end

-- WebSocket 客户端创建异常测试:全参数（无无效参数，应创建成功）
function websocket_tests.test_WebsocketCreate_default()
    local wsc = websocket.create(nil, "ws://echo.airtun.air32.cn/ws/echo", 120, true)
    assert(wsc ~= nil, "WebSocket 客户端创建失败了")
    assert(type(wsc) == "userdata", string.format("返回值类型应该为userdata,实际是%s:", type(wsc)))
    -- 创建成功就关闭，避免资源泄露
    wsc:close()
end

-- 测试服务器
local test_server = "ws://airtest.openluat.com:2900/websocket"

-- 测试数据 - 每种10次回环

-- 测试2: WebSocket客户端创建并设置请求头测试
-- 参数格式为：table,
function websocket_tests.test_WebsocketCreate_with_headers_table()
    local wsc = websocket.create(nil, test_server)
    assert(wsc ~= nil, "WebSocket 客户端创建失败了")
    assert(type(wsc) == "userdata", string.format("返回值类型应该为userdata,实际是%s:", type(wsc)))

    local success, err = pcall(function()

        wsc:headers({
            Auth = "Basic ABCDEGG",
            TestType = "echo_test"
        })

    end)
    assert(success == true, "参数类型为table,设置自定义请求头失败，失败原因是", err)
    wsc:close()
end

-- 参数格式为：string,
function websocket_tests.test_WebsocketCreate_with_headers_string()
    local wsc = websocket.create(nil, test_server)
    assert(wsc ~= nil, "WebSocket 客户端创建失败了")
    assert(type(wsc) == "userdata", string.format("返回值类型应该为userdata,实际是%s:", type(wsc)))

    local success, err = pcall(function()

        wsc:headers("Auth: Basic ABCDERG\r\n")

    end)
    assert(success == true, "参数类型为string,设置自定义请求头失败，失败原因是", err)
    wsc:close()
end

-- 测试3: WebSocket客户端创建连接测试
function websocket_tests.test_WebsocketCreate_and_connect()
    local wsc = websocket.create(nil, test_server)
    assert(wsc ~= nil, "WebSocket 客户端创建失败了")
    assert(type(wsc) == "userdata", string.format("返回值类型应该为userdata,实际是%s:", type(wsc)))

    local connect_result = wsc:connect()

    assert(type(connect_result) == "boolean",
        string.format("返回值类型应该为boolean,实际是%s:", type(connect_result)))

    assert(connect_result == true, "WebSocket 连接请求发送失败")
    -- 等待连接
    sys.wait(1000)
    wsc:close()
end

-- 三种不同数据

local test_cases = {
    ["简单文本"] = {
        data = "hello world",
        opt = nil, -- 使用默认参数 --简单发送文本数据
        description = "发送文本数据（使用默认参数）"
    },
    ["显式文本"] = {
        data = "hello world",
        opt = 0,
        description = "显式发送文本数据"
    },
    ["JSON数据"] = {
        data = {
            action = "echo",
            msg = "test",
            timestamp = os.time()
        },
        opt = 0,
        description = "发送JSON数据"
    }
}

-- 拆出的全局函数
local function send_test_data(client, state, test_case_name)
    -- 检查是否应该继续发送
    if state.sent_count >= 10 then
        return
    end
    
    local test_case = test_cases[test_case_name]
    assert(test_case ~= nil, "类型错误，未知的测试类型: " .. test_case_name)
    
    local ready = client:ready()
    assert(ready == true, "WebSocket 客户端未就绪")
    
    state.sent_count = state.sent_count + 1
    
    -- 获取要发送的数据
    local data_to_send
    if type(test_case.data) == "function" then
        data_to_send = test_case.data()
    else
        data_to_send = test_case.data
    end
    
    -- 记录发送的数据
    state.sent_data[state.sent_count] = data_to_send
    log.info("发送" .. test_case.description, "第", state.sent_count, "次", "长度:", #data_to_send)

    local send_result
    if test_case.opt then
        send_result = client:send(data_to_send, test_case.opt)
    else
        send_result = client:send(data_to_send)
    end
    
    -- 使用断言验证发送结果
    assert(send_result == true, 
        string.format("第%d次发送失败，类型: %s", state.sent_count, test_case_name))
    
    log.info("发送成功", "第", state.sent_count, "次", "类型:", test_case_name)

    -- 如果是最后一次发送，设置超时检查
    if state.sent_count >= 10 then
        log.info("已发送完10次，等待接收")
        sys.timerStart(function()
            if state.received_count < 10 then
                assert(false, string.format("等待响应超时，已发送%d次，只收到%d次", 
                      state.sent_count, state.received_count))
            end
        end, 5000)
    end
end

function websocket_tests.test_WebsocketEcho_simple_text()
    local test_case_name = "简单文本"
    -- 1. 创建客户端
    local wsc = websocket.create(nil, test_server)
    assert(wsc ~= nil, "WebSocket 客户端创建失败了")
    assert(type(wsc) == "userdata", string.format("返回值类型应该为userdata,实际是%s:", type(wsc)))

    -- 2. 设置请求头
    wsc:headers({
        Auth = "Basic ABCDEGG",
        TestType = "echo_test"
    })

    -- 3. 设置自动重连
    wsc:autoreconn(true)

    -- 测试状态
    local test_state = {
        sent_count = 0,
        received_count = 0,
        sent_data = {}, -- 记录每次发送的数据
        received_data = {}, -- 记录每次接收的数据
        send_timer = nil -- 新增：定时器引用
    }
    -- 4. 设置回调函数
    wsc:on(function(ws_client, event, data, fin, optcode)
        log.info("WebSocket事件", event)
        if event == "conack" then
            log.info("WebSocket连接成功")
            test_state.send_timer = sys.timerStart(function()
                send_test_data(wsc, test_state, test_case_name)
            end, 3000)
        elseif event == "recv" then
            if data then
                test_state.received_count = test_state.received_count + 1
                -- 记录接收的数据
                test_state.received_data[test_state.received_count] = data

                -- 验证数据一致性（每次收到都验证）--考虑接收延迟 
                if test_state.sent_count >= test_state.received_count then
                    -- 记录
                    local sent_data = test_state.sent_data[test_state.received_count]
                    assert(sent_data ~= nil, string.format("第%d次接收数据时，对应的发送数据不存在",
                        test_state.received_count))
                    assert(sent_data == data, string.format("第%d次数据不一致\n发送: %s\n接收: %s",
                        test_state.received_count, sent_data, data))
                    log.info("✅ 第" .. test_state.received_count .. "次数据一致")
                end
                if test_state.sent_count < 10 then
                    -- 3秒后发送下一次
                    test_state.send_timer = sys.timerStart(function()
                        send_test_data(wsc, test_state, test_case_name)
                    end, 3000)
                elseif test_state.received_count >= 10 then
                    log.info("测试完成，准备关闭连接")
                    wsc:close()
                end
            end
        elseif event == "sent" then
            log.debug("发送确认")

        elseif event == "disconnect" then
            log.warn("连接断开")
            if test_state.send_timer then
                sys.timerStop(test_state.send_timer)
                test_state.send_timer = nil
            end

        elseif event == "error" then
            log.error("WebSocket错误", data)
            if test_state.send_timer then
                sys.timerStop(test_state.send_timer)
                test_state.send_timer = nil
            end
            -- 遇到错误时抛出断言
            assert(false, string.format("WebSocket错误: %s", data or "未知错误"))
        end
    end)
    -- 5.连接服务器
    local connect_result = wsc:connect()
    assert(connect_result == true, "WebSocket 连接请求发送失败")
    log.info("正在连接WebSocket服务器...")

    --
    local start = os.time()
    while test_state.sent_count < 10 or test_state.received_count < 10 do
        assert(os.time() - start <= 60, "测试超时")
        sys.wait(1000)
    end

    -- 清理和验证
    sys.timerStop(test_state.send_timer)

    assert(test_state.sent_count == 10 and test_state.received_count == 10, "发送/接收未达10次")
    log.info("========== 测试完成 ==========")

    -- 关闭连接
    if wsc then
        wsc:close()
        wsc = nil
    end
end

return websocket_tests
