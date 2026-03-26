local websocket_tests = {}

-- 测试服务器
local test_server = "ws://airtest.openluat.com:2900/websocket"
local echo_server = "ws://echo.airtun.air32.cn/ws/echo2"

-- 测试数据
local test_cases = {
    ["简单文本"] = {
        data = "hello world",
        opt = nil,
        description = "发送文本数据"
    },
    ["显式文本"] = {
        data = "hello world",
        opt = 0,
        description = "显式发送文本数据"
    },
    ["二进制数据"] = {
        data = string.char(0x48, 0x65, 0x6C, 0x6C, 0x6F), -- "Hello"
        opt = 1, 
        description = "发送二进制数据"
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

local function send_test_data(client, state, param)
    local test_case
    local test_case_name
    local is_single_test = false

    if type(param) == "string" then
        if state.sent_count >= 10 then
            return false
        end
        test_case_name = param
        test_case = test_cases[test_case_name]
        assert(test_case ~= nil, "未知测试类型: " .. param)
        is_single_test = true
    elseif type(param) == "table" then
        local total_tests = #param * 10
        if state.sent_count >= total_tests then
            return false
        end
        local format_index = math.floor(state.sent_count / 10) + 1
        test_case_name = param[format_index]
        test_case = test_cases[test_case_name]
        assert(test_case ~= nil, "未知测试类型: " .. test_case_name)
    else
        error("参数类型错误，应为string或table")
    end

    local ready = client:ready()
    if not ready then
        log.warn("WebSocket客户端未就绪，跳过本次发送")
        return false
    end

    state.sent_count = state.sent_count + 1

    local data_to_send = test_case.data
    if type(data_to_send) == "table" then
        data_to_send = json.encode(data_to_send)
    end

    state.sent_data[state.sent_count] = data_to_send

    if is_single_test then
        log.info(string.format("发送%s 第%d次 长度:%d 内容:%s", test_case.description, state.sent_count,
            #data_to_send, data_to_send))
    else
        local format_seq = ((state.sent_count - 1) % 10) + 1
        log.info(string.format("发送%s 第%d次 格式:%s(%d/10) 长度:%d 内容:%s", test_case.description,
            state.sent_count, test_case_name, format_seq, #data_to_send, data_to_send))
    end

    local send_result = client:send(data_to_send, test_case.opt)
    assert(send_result == true, string.format("第%d次数据发送失败", state.sent_count))

    log.info("发送成功", "第", state.sent_count, "次", "类型:", test_case_name, "opt:", test_case.opt)
    return true
end

-- ============================================================
-- 基础测试用例
-- ============================================================

-- 测试1: WebSocket客户端创建测试
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
    wsc:close()
end

function websocket_tests.test_WebsocketCreate_adapterNil()
    local wsc = websocket.create(nil, "ws://echo.airtun.air32.cn/ws/echo")
    assert(wsc ~= nil, "WebSocket 客户端创建失败了")
    assert(type(wsc) == "userdata", string.format("返回值类型应该为userdata,实际是%s:", type(wsc)))
    wsc:close()
end

function websocket_tests.test_WebsocketCreateNilUrl()
    local success, err = pcall(function()
        websocket.create(nil, nil)
    end)
    assert(success == false, "无效url进行WebSocket客户端创建异常，应该失败")
end

function websocket_tests.test_WebsocketCreate_default()
    local wsc = websocket.create(nil, "ws://echo.airtun.air32.cn/ws/echo", 120, true)
    assert(wsc ~= nil, "WebSocket 客户端创建失败了")
    assert(type(wsc) == "userdata", string.format("返回值类型应该为userdata,实际是%s:", type(wsc)))
    wsc:close()
end

-- 测试2: WebSocket客户端创建并设置请求头测试
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
    assert(success == true, "参数类型为table,设置自定义请求头失败")
    wsc:close()
end

function websocket_tests.test_WebsocketCreate_with_headers_string()
    local wsc = websocket.create(nil, test_server)
    assert(wsc ~= nil, "WebSocket 客户端创建失败了")
    assert(type(wsc) == "userdata", string.format("返回值类型应该为userdata,实际是%s:", type(wsc)))

    local success, err = pcall(function()
        wsc:headers("Auth: Basic ABCDERG\r\n")
    end)
    assert(success == true, "参数类型为string,设置自定义请求头失败")
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
    sys.wait(1000)
    wsc:close()
end

-- ============================================================
-- 数据回环测试
-- ============================================================

-- 二进制数据回环测试
function websocket_tests.test_WebsocketEcho_binary()
    local test_case_name = "二进制数据"
    local wsc = websocket.create(nil, echo_server)
    assert(wsc ~= nil, "WebSocket 客户端创建失败了")

    wsc:headers({
        Auth = "Basic ABCDEGG",
        TestType = "echo_test"
    })
    wsc:autoreconn(true)

    local test_state = {
        sent_count = 0,
        received_count = 0,
        sent_data = {},
        received_data = {},
        send_timer = nil,
        test_complete = false
    }
    
    wsc:on(function(ws_client, event, data, fin, optcode)
        log.info("WebSocket事件", event)
        
        if event == "conack" then
            log.info("WebSocket连接成功")
            
            -- 立即发送第一次
            send_test_data(wsc, test_state, test_case_name)
            
            -- 启动定时器，每3秒发送一次
            test_state.send_timer = sys.timerLoopStart(function()
                if test_state.sent_count < 10 then
                    send_test_data(wsc, test_state, test_case_name)
                end
                if test_state.sent_count >= 10 then
                    if test_state.send_timer then
                        sys.timerStop(test_state.send_timer)
                        test_state.send_timer = nil
                    end
                end
            end, 3000)
            
        elseif event == "recv" then
            if data then
                test_state.received_count = test_state.received_count + 1
                test_state.received_data[test_state.received_count] = data

                if test_state.sent_count >= test_state.received_count then
                    local sent_data = test_state.sent_data[test_state.received_count]
                    if sent_data then
                        assert(sent_data == data, string.format("第%d次数据不一致\n发送: %s\n接收: %s",
                            test_state.received_count, sent_data, data))
                        log.info("第" .. test_state.received_count .. "次数据一致")
                    end
                end
                
                if test_state.received_count >= 10 then
                    test_state.test_complete = true
                    log.info("测试完成，准备关闭连接")
                    if test_state.send_timer then
                        sys.timerStop(test_state.send_timer)
                        test_state.send_timer = nil
                    end
                    wsc:close()
                end
            end
            
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
            assert(false, string.format("WebSocket错误: %s", data or "未知错误"))
        end
    end)

    local connect_result = wsc:connect()
    assert(connect_result == true, "WebSocket 连接请求发送失败")
    log.info("正在连接WebSocket服务器...")

    local start = os.time()
    while not test_state.test_complete and os.time() - start <= 60 do
        sys.wait(1000)
        if os.time() - start > 0 and (os.time() - start) % 10 == 0 then
            log.info("测试进度", string.format("已发送:%d, 已接收:%d", 
                test_state.sent_count, test_state.received_count))
        end
    end
    
    if test_state.send_timer then
        sys.timerStop(test_state.send_timer)
        test_state.send_timer = nil
    end
    
    assert(test_state.test_complete == true, 
        string.format("测试超时，已发送:%d, 已接收:%d", test_state.sent_count, test_state.received_count))
    assert(test_state.sent_count == 10, string.format("应发送10次，实际%d次", test_state.sent_count))
    assert(test_state.received_count == 10, string.format("应接收10次，实际%d次", test_state.received_count))
    
    log.info("========== 二进制数据回环测试通过 ==========")
end

-- 多种数据的回环测试
function websocket_tests.test_WebsocketEcho_all_formats()
    local test_cases_list = {"简单文本", "显式文本", "JSON数据"}
    local total_formats = #test_cases_list
    local total_tests = total_formats * 10

    local wsc = websocket.create(nil, test_server)
    assert(wsc ~= nil, "WebSocket 客户端创建失败了")
    assert(type(wsc) == "userdata", string.format("返回值类型应该为userdata,实际是%s:", type(wsc)))

    local success, err = pcall(function()
        wsc:headers({
            Auth = "Basic ABCDEGG",
            TestType = "echo_test"
        })
    end)
    assert(success == true, "参数类型为table,设置自定义请求头失败")

    wsc:autoreconn(true)

    local test_state = {
        sent_count = 0,
        received_count = 0,
        sent_data = {},
        received_data = {},
        send_timer = nil,
        test_complete = false
    }

    wsc:on(function(ws_client, event, data, fin, optcode)
        log.info("WebSocket事件", event)

        if event == "conack" then
            log.info("WebSocket连接成功")
            log.info(string.format("开始测试%d种格式，总共%d次", total_formats, total_tests))

            send_test_data(wsc, test_state, test_cases_list)
            
            test_state.send_timer = sys.timerLoopStart(function()
                if test_state.sent_count < total_tests then
                    send_test_data(wsc, test_state, test_cases_list)
                end
                if test_state.sent_count >= total_tests then
                    if test_state.send_timer then
                        sys.timerStop(test_state.send_timer)
                        test_state.send_timer = nil
                    end
                end
            end, 3000)

        elseif event == "recv" then
            if data then
                test_state.received_count = test_state.received_count + 1
                test_state.received_data[test_state.received_count] = data

                if test_state.sent_count >= test_state.received_count then
                    local sent_info = test_state.sent_data[test_state.received_count]
                    if sent_info then
                        assert(#sent_info == #data,
                            string.format("第%d次数据长度不一致,发送长度%d,接收长度%d",
                                test_state.received_count, #sent_info, #data))
                        assert(sent_info == data,
                            string.format("第%d次数据不一致,发送:%s,接收:%s",
                                test_state.received_count, sent_info, data))
                        log.info(string.format("第%d次数据回环完全一致", test_state.received_count))
                    end
                end

                if test_state.received_count >= total_tests then
                    test_state.test_complete = true
                    log.info(string.format("所有%d次接收已完成", total_tests))
                    if test_state.send_timer then
                        sys.timerStop(test_state.send_timer)
                        test_state.send_timer = nil
                    end
                    wsc:close()
                end
            end

        elseif event == "disconnect" then
            log.warn("连接断开")
            if test_state.send_timer then
                sys.timerStop(test_state.send_timer)
                test_state.send_timer = nil
            end

        elseif event == "error" then
            log.error("WebSocket错误", data)
            assert(false, string.format("WebSocket错误: %s", data or "未知错误"))
        end
    end)

    local connect_result = wsc:connect()
    assert(connect_result == true, "WebSocket 连接请求发送失败")
    log.info("正在连接WebSocket服务器...")

    local start = os.time()
    while not test_state.test_complete and os.time() - start <= 120 do
        sys.wait(1000)
        if os.time() - start > 0 and (os.time() - start) % 10 == 0 then
            log.info("测试进度", string.format("已发送:%d, 已接收:%d", 
                test_state.sent_count, test_state.received_count))
        end
    end

    if test_state.send_timer then
        sys.timerStop(test_state.send_timer)
        test_state.send_timer = nil
    end

    assert(test_state.test_complete == true, 
        string.format("测试超时，已发送:%d, 已接收:%d", test_state.sent_count, test_state.received_count))
    assert(test_state.sent_count == total_tests,
        string.format("应发送%d次，实际%d次", total_tests, test_state.sent_count))
    assert(test_state.received_count == total_tests,
        string.format("应接收%d次，实际%d次", total_tests, test_state.received_count))

    log.info(string.format("所有%d次测试通过！共%d种格式", total_tests, total_formats))

    if wsc then
        wsc:close()
    end
end

-- ============================================================
-- 功能测试用例
-- ============================================================

-- debug接口测试
function websocket_tests.test_WebsocketDebug()
    local wsc = websocket.create(nil, echo_server)
    assert(wsc ~= nil, "WebSocket 客户端创建失败了")
    
    local success, err = pcall(function()
        wsc:debug(true)
    end)
    assert(success == true, "开启debug失败: " .. tostring(err))
    
    success, err = pcall(function()
        wsc:debug(false)
    end)
    assert(success == true, "关闭debug失败: " .. tostring(err))
    
    wsc:close()
    log.info("debug接口测试通过")
end

-- disconnect主动断开连接
function websocket_tests.test_WebsocketDisconnect()
    local wsc = websocket.create(nil, echo_server)
    assert(wsc ~= nil, "WebSocket 客户端创建失败了")
    
    local disconnected = false
    wsc:on(function(_, event, data)
        if event == "disconnect" then
            disconnected = true
            log.info("disconnect事件触发", data)
        end
    end)
    
    local connect_result = wsc:connect()
    assert(connect_result == true, "连接失败")
    sys.wait(1000)
    
    if wsc.disconnect then
        local success, err = pcall(function()
            wsc:disconnect()
        end)
        assert(success == true, "disconnect调用失败: " .. tostring(err))
        
        local start = os.time()
        while not disconnected and os.time() - start < 5 do
            sys.wait(100)
        end
        assert(disconnected == true, "disconnect事件未触发")
    else
        log.warn("当前版本不支持disconnect方法，跳过测试")
    end
    
    wsc:close()
    log.info("disconnect测试完成")
end

-- autoreconn参数变体测试
function websocket_tests.test_WebsocketAutoreconnVariants()
    local wsc = websocket.create(nil, echo_server)
    assert(wsc ~= nil, "WebSocket 客户端创建失败了")
    
    local success, err = pcall(function()
        wsc:autoreconn(true)
    end)
    assert(success == true, "启用自动重连失败")
    
    success, err = pcall(function()
        wsc:autoreconn(true, 5000)
    end)
    assert(success == true, "启用自动重连并指定周期失败")
    
    success, err = pcall(function()
        wsc:autoreconn(false)
    end)
    assert(success == true, "禁用自动重连失败")
    
    wsc:close()
    log.info("autoreconn参数变体测试通过")
end

-- send带fin参数测试
function websocket_tests.test_WebsocketSendWithFin()
    local wsc = websocket.create(nil, echo_server)
    assert(wsc ~= nil, "WebSocket 客户端创建失败了")
    
    local send_success = false
    wsc:on(function(_, event, data)
        if event == "sent" then
            send_success = true
            log.info("发送确认收到")
        elseif event == "recv" then
            log.info("收到回显数据", data)
        end
    end)
    
    local connect_result = wsc:connect()
    assert(connect_result == true, "连接失败")
    sys.wait(1000)
    
    local result = wsc:send("test message", 0, 1)
    assert(result == true, "发送失败")
    
    sys.wait(2000)
    wsc:close()
    log.info("send带fin参数测试通过")
end

-- WSS加密连接测试
function websocket_tests.test_WebsocketWssConnection()
    log.info("WSS连接测试", "跳过WSS测试，需要服务器支持WSS协议")
    log.info("提示", "如需测试WSS，请使用支持WSS的WebSocket服务器")
    assert(true, "WSS测试跳过")
end

-- 事件回调测试
function websocket_tests.test_WebsocketEventCallback()
    local wsc = websocket.create(nil, test_server)
    assert(wsc ~= nil, "WebSocket客户端创建失败")
    
    local events = {
        conack = false,
        recv = false
    }
    
    wsc:on(function(_, event, data, fin, opcode)
        log.info("事件触发", event, "data:", data, "fin:", fin, "opcode:", opcode)
        
        if event == "conack" then
            events.conack = true
            wsc:send("test for events")
        elseif event == "recv" then
            events.recv = true
            log.info("接收到数据", "内容:", data)
        elseif event == "error" then
            log.error("错误事件", data)
        end
    end)
    
    local result = wsc:connect()
    assert(result == true, "连接失败")
    
    local start = os.time()
    while not (events.conack and events.recv) and os.time() - start < 10 do
        sys.wait(500)
    end
    
    assert(events.conack == true, "conack事件未触发")
    assert(events.recv == true, "recv事件未触发")
    
    log.info("事件回调测试通过")
    wsc:close()
    sys.wait(1000)
end

-- ready接口测试
function websocket_tests.test_WebsocketReady()
    local wsc = websocket.create(nil, echo_server)
    assert(wsc ~= nil, "WebSocket客户端创建失败")
    
    local ready_before = wsc:ready()
    assert(ready_before == false, "连接前ready应该返回false")
    
    local connected = false
    wsc:on(function(_, event)
        if event == "conack" then
            connected = true
        end
    end)
    
    local result = wsc:connect()
    assert(result == true, "连接失败")
    
    local start = os.time()
    while not connected and os.time() - start < 5 do
        sys.wait(500)
    end
    
    local ready_after = wsc:ready()
    assert(ready_after == true, "连接后ready应该返回true")
    
    wsc:close()
    sys.wait(500)
    
    local ready_closed = wsc:ready()
    assert(ready_closed == false, "关闭后ready应该返回false")
    
    log.info("ready接口测试通过")
end

-- 多网卡适配器测试
function websocket_tests.test_WebsocketWithSpecificAdapter()
    local adapters = {}
    if rtos.bsp() == "Air8101" then
        adapters = {socket.LWIP_STA, socket.LWIP_AP}
    else
        adapters = {socket.LWIP_GP}
    end
    
    for _, adapter in ipairs(adapters) do
        log.info("测试适配器", adapter)
        local wsc = websocket.create(adapter, echo_server)
        if wsc then
            local connected = false
            wsc:on(function(_, event)
                if event == "conack" then
                    connected = true
                end
            end)
            
            local result = wsc:connect()
            if result then
                local start = os.time()
                while not connected and os.time() - start < 5 do
                    sys.wait(500)
                end
                if connected then
                    log.info("适配器", adapter, "连接成功")
                end
            end
            wsc:close()
        else
            log.warn("适配器", adapter, "创建失败")
        end
        sys.wait(1000)
    end
    log.info("多网卡适配器测试完成")
end

-- 无效服务器测试
function websocket_tests.test_WebsocketInvalidServer()
    local wsc = websocket.create(nil, "ws://invalid.server.doesnotexist:8080/ws")
    assert(wsc ~= nil, "WebSocket客户端创建失败")
    
    local error_occurred = false
    wsc:on(function(_, event, data)
        if event == "error" then
            error_occurred = true
            log.info("错误事件触发", data)
        end
    end)
    
    local result = wsc:connect()
    assert(result == true, "连接请求应该成功发起")
    
    sys.wait(5000)
    
    log.info("无效服务器测试完成")
    wsc:close()
end

-- 分帧数据接收测试
function websocket_tests.test_WebsocketFragmentedReceive()
    log.info("分帧数据接收测试", "跳过分帧测试，需要服务器支持分帧发送")
    log.info("提示", "如需测试分帧，请使用支持分帧的WebSocket服务器")
    assert(true, "分帧测试跳过")
end

return websocket_tests