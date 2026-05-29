--[[
@module  http_upload_stream
@summary HTTP流式上传模块，通过UART获取数据后使用fill_data_func流式上传到服务器
@version 1.0
@date    2025.08.06
@author  马梦阳
@usage
本文件为HTTP流式上传模块，核心业务逻辑为：
1. 向uart_app模块请求文件大小（GET_FILE_SIZE_REQ/RESP消息对）
2. 向uart_app模块分片请求文件数据（GET_FILE_DATA_REQ/RESP消息对）
3. 使用httpplus扩展库的fill_data_func流式上传功能，将数据上传到服务器
4. 上传服务器地址：https://airtest.luatos.com/iot/luat_test_file/add

与uart_app模块的消息交互流程：
  http_upload_stream                    uart_app
       |                                    |
       |-- GET_FILE_SIZE_REQ ------------->|
       |<----------- GET_FILE_SIZE_RESP ---|
       |                                    |
       |-- GET_FILE_DATA_REQ(index) ------>|  (循环，每次由fill_data_func触发)
       |<----------- GET_FILE_DATA_RESP ---|

本文件没有对外接口，直接在main.lua中require "http_upload_stream"就可以加载运行
]]

local httpplus = require "httpplus"



-- fill_data_func: 每次被httpplus底层调用时，向uart_app请求下一片数据
-- @param total_sent 已发送的总字节数
-- @param sent_count 已调用fill_data_func的次数
-- @return zbuff数据 或 nil(数据源耗尽)
local function fill_stream_data(total_sent, sent_count)
    log.info("fill_stream_data", total_sent, sent_count)
    sys.publish("GET_FILE_DATA_REQ", total_sent + 1)
    local result, data = sys.waitUntil("GET_FILE_DATA_RESP", 10000)
    if result then
        if type(data) == "string" then
            log.info("fill_stream_data", "GET_FILE_DATA_RESP", data:len())
        else
            log.info("fill_stream_data", "GET_FILE_DATA_RESP", data:used())
        end
        return data
    else
        log.error("http_upload_stream", "GET_FILE_DATA_RESP timeout", total_sent)
        return
    end
end

-- HTTP流式上传任务的主处理函数
local function http_upload_task_func() 

    local code, response

    while true do
        -- 向uart_app请求文件大小
        sys.publish("GET_FILE_SIZE_REQ")
        local result, file_size = sys.waitUntil("GET_FILE_SIZE_RESP", 10000)
        if not result then
            log.error("http_upload_stream", "GET_FILE_SIZE_RESP timeout")
            goto LOOP_PROC
        end

        log.info("http_upload_stream", "file_size", file_size)

        -- 等待网络就绪
        while not socket.adapter(socket.dft()) do
            log.warn("http_upload_stream", "wait IP_READY", socket.dft())
            sys.waitUntil("IP_READY", 1000)
        end
        log.info("http_upload_stream", "recv IP_READY", socket.dft())

        -- 使用httpplus流式上传接口上传文件数据
        -- files中["f"]的value为table类型，表示流式上传：
        --   size: 文件总字节数，由uart_app通过串口获取
        --   fill_data_func: 填充函数，httpplus底层循环调用获取分片数据
        --   filename: 上传到服务器的文件名
        -- 服务器要求文件name必须使用"f"，文本name必须使用"params"
        -- 测试接口响应：成功 HTTP 200 {"code":0,"value":"上传成功"}
        -- 网页端查看：https://iot.luatos.com/#/p8000/netlab_file_server
        code, response = httpplus.request(
        {
            url = "https://airtest.luatos.com/iot/luat_test_file/add",
            files =
            {
                ["f"] = 
                {
                    size = file_size,
                    filename = "uart_to_http_stream.bin",
                    fill_data_func = fill_stream_data
                }
            },
            forms =
            {
                ["params"] = json.encode({
                    username = "LuatOS",
                    password = "1234567890"
                }),
            },
            -- 超时时间与数据长度关联: 1000bytes/s保守速率, 最低60秒
            timeout = math.max(60, math.ceil(file_size / 1000))
        })
        log.info("http_upload_stream", code==200 and "success" or "error", code)
        if code==200 then
            log.info("http_upload_stream", "headers", json.encode(response.headers or {}))
            local body = response.body:query()
            log.info("http_upload_stream", "body", body and (body:len()>1024 and body:len() or body) or "nil")
        end

        ::LOOP_PROC::
        -- 60秒之后，循环测试
        sys.wait(60000)
    end
end

-- 创建并且启动一个task
sys.taskInit(http_upload_task_func)
