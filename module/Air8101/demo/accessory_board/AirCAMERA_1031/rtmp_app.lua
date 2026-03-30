--[[
@module  rtmp_app
@summary USB摄像头RTMP推流功能模块
@version 1.0
@date    2026.01.15
@author  王城钧
@usage
本文件为USB摄像头RTMP推流功能模块，核心业务逻辑为：
1. USB 摄像头初始化、帧率配置与H264视频编码
2. 通过HTTP请求获取RTMP推流地址
3. 连接RTMP服务器并进行视频推流
]]

-- 引入excamera扩展库
local excamera = require("excamera")

local RTMP_TASK_NAME = "rtmp_app_task" -- RTMP任务名称

-- HTTP请求获取RTMP服务器地址函数
local function rtmp_http_request()
    local get_device_id = netdrv.mac(socket.LWIP_STA) -- Air8101用STA MAC作为设备ID
    log.info("打印设备的ID号", get_device_id)

    local url = "http://video.luatos.com:10030/api-system/deviceVideo/get" .. "/" .. get_device_id
    log.info("打印的URL", url)
    local camera_header = {
        ["Accept-Encoding"] = "identity",
        ["Host"] = "video.luatos.com:10030",
        ["Content-Type"] = "application/json"
    }
    local post_body = {
        deviceAccess = "8",     -- 8 代表接入方式为RTMP
        deviceUser = "admin",   -- 平台录像机设置的设备用户（不是登录用的用户名）
        devicePsd = "Air123456" -- 平台录像机设置的设备密码（不是登录用的密码）
    }
    -- 发送POST请求并等待响应
    local code, headers, body = http.request("POST", url, camera_header, json.encode(post_body)).wait()
    log.info("打印的请求code", code)

    if code ~= 200 then
        log.error("HTTP请求失败")
        return false, nil
    end

    log.info("打印的请求body", body)
    local json_body = json.decode(body)
    if not json_body or json_body.code ~= 200 then
        log.error("请求视频URL失败", json_body and json_body.msg or "未知错误")
        return false, nil
    end

    local rtmp_url = json_body.data.urlList[1]
    log.info("请求得到的RTMP地址", rtmp_url)
    if not rtmp_url then
        log.error("未获取到RTMP地址")
        return false, nil
    end
    return true, rtmp_url
end


local g_s_rtmp_state

-- RTMP状态回调函数
-- 连接过程中，如果连接失败，state状态依次为STATE_IDLE->STATE_DISCONNECTING->STATE_IDLE->STATE_ERROR
-- 已经建立了连接，推流过程中，如果本地调用disconnect接口，state状态依次为STATE_IDLE->STATE_DISCONNECTING->STATE_IDLE
-- 已经建立了连接，推流过程中，如果网络或者服务器出现了异常，或者本地发送数据出现了异常，state状态依次为STATE_IDLE->STATE_DISCONNECTING->STATE_IDLE->STATE_ERROR
local function rtmp_state_callback(state)
    -- 打印RTMP状态变化基础日志
    log.info("rtmp_state_callback state", state)

    -- 根据不同状态执行对应逻辑
    if state == rtmp.STATE_IDLE then
        log.info("空闲状态，可能和推流时效有关，需要等待一段时间，再尝试重连")
        if g_s_rtmp_state==rtmp.STATE_DISCONNECTING then
            sys.sendMsg(RTMP_TASK_NAME, "RTMP_EVENT", "DISCONNECTED")
        end
    elseif state == rtmp.STATE_CONNECTING then
        log.info("正在连接")
    elseif state == rtmp.STATE_HANDSHAKING then
        log.info("握手中")
    elseif state == rtmp.STATE_CONNECTED then
        log.info("已连接")
        sys.sendMsg(RTMP_TASK_NAME, "RTMP_EVENT", "CONNECTED")
    elseif state == rtmp.STATE_PUBLISHING then
        log.info("推流中")
    elseif state == rtmp.STATE_DISCONNECTING then
        log.info("正在断开")
    elseif state == rtmp.STATE_ERROR then
        log.info("错误")
    end
    g_s_rtmp_state = state
end

-- RTMP main task 的任务处理函数
local function rtmp_task()
    local camera_opened, msg, rtmpc, success, rtmp_url

    while true do
        -- 1. 如果当前时间点设置的默认网卡还没有连接成功，一直在这里循环等待
        while not socket.adapter(socket.dft()) do
            log.warn("rtmp_task", "wait IP_READY", socket.dft())
            -- 在此处阻塞等待默认网卡连接成功的消息"IP_READY"
            -- 或者等待1秒超时退出阻塞等待状态;
            -- 注意：此处的1000毫秒超时不要修改的更长；
            -- 因为当使用exnetif.set_priority_order配置多个网卡连接外网的优先级时，会隐式的修改默认使用的网卡
            -- 当exnetif.set_priority_order的调用时序和此处的socket.adapter(socket.dft())判断时序有可能不匹配
            -- 此处的1秒，能够保证，即使时序不匹配，也能1秒钟退出阻塞状态，再去判断socket.adapter(socket.dft())
            sys.waitUntil("IP_READY", 1000)
        end

        -- 检测到了IP_READY消息
        log.info("rtmp_task", "recv IP_READY", socket.dft())

        -- 清空此task绑定的消息队列中的未处理的消息
        sys.cleanMsg(RTMP_TASK_NAME)

        -- 2. HTTP请求获取RTMP服务器地址
        success, rtmp_url = rtmp_http_request()
        if not success then
            log.error("获取RTMP地址失败")
            goto EXCEPTION_PROC
        end

        -- 3. 配置摄像头
        camera_opened = excamera.open({
            id = camera.USB,
            sensor_width = 1280,
            sensor_height = 720,
            usb_port = 1
        })
        
        if not camera_opened then
            log.error("摄像头初始化失败")
            goto EXCEPTION_PROC
        end

        -- 启动摄像头
        log.info("启动摄像头...")
        if not excamera.rtmp() then
            log.error("无法启动摄像头")
            goto EXCEPTION_PROC
        end

        -- 创建RTMP客户端
        rtmpc = rtmp.create(rtmp_url)
        if not rtmpc then
            log.error("rtmp.create", "创建RTMP客户端失败")
            goto EXCEPTION_PROC
        end
        log.info("rtmp.create", "RTMP客户端创建成功")

        -- 设置RTMP状态回调
        rtmpc:setCallback(rtmp_state_callback)

        -- 连接RTMP服务器
        log.info("开始连接RTMP服务器...")
        success = rtmpc:connect()
        if not success then
            log.error("连接RTMP服务器失败")
            goto EXCEPTION_PROC
        end

        -- 推流状态的处理调度逻辑
        while true do
            -- 等待消息
            msg = sys.waitMsg(RTMP_TASK_NAME, "RTMP_EVENT")
            if msg then
                log.info("rtmp_task waitMsg", msg[2], msg[3], msg[4])

                -- 连接成功
                if msg[2] == "CONNECTED" then
                    -- 直接启动推流，不检查返回值
                    log.info("准备开始推流")
                    rtmpc:start()
                    log.info("推流已启动")

            -- 连接失败/连接断开
            elseif msg[2] == "DISCONNECTED" then
                break

            -- 需要主动关闭连接
            -- 用户需要主动关闭rtmp连接时，可以调用sys.sendMsg(RTMP_TASK_NAME, "RTMP_EVENT", "CLOSE")
            elseif msg[2] == "CLOSE" then
                -- 主动断开rtmp client连接
                rtmpc:disconnect()
            end
            end
        end

        -- 出现异常
        ::EXCEPTION_PROC::

        -- 清空此task绑定的消息队列中的未处理的消息
        sys.cleanMsg(RTMP_TASK_NAME)

        -- 5. 关闭推流
        log.info("推流结束，开始释放资源")

        -- 关闭摄像头
        if camera_opened then
            excamera.close()
            log.info("excamera已关闭")
        end

        -- 关闭RTMP客户端
        if rtmpc then
            rtmpc:stop()
            log.info("RTMP推流已停止")
            rtmpc:disconnect()
            log.info("RTMP连接已断开")
            rtmpc:destroy()
            log.info("RTMP客户端已销毁")
        end

        -- 确保所有状态重置
        log.info("所有资源已释放，5秒后重连")

        -- 5秒后跳转到循环体开始位置，自动发起重连
        sys.wait(5000)
    end
end

local function wifi_sta_func(evt, data)
    -- evt 可能的值有: "CONNECTED", "DISCONNECTED"
    -- 当evt=CONNECTED, data是连接的AP的ssid, 字符串类型
    -- 当evt=DISCONNECTED, data断开的原因, 整数类型
    log.info("收到STA事件", evt, data)
    if evt == "DISCONNECTED" then
        sys.sendMsg(RTMP_TASK_NAME, "RTMP_EVENT", "DISCONNECTED")
    end
end

-- 内存检查函数
local function memory_check()
    while true do
        -- 等待20秒
        sys.wait(20000)
        -- 打印系统内存使用信息
        log.info("系统内存使用情况", rtos.meminfo("sys"))
        -- 打印Lua虚拟机内存使用信息
        log.info("Lua虚拟机内存使用情况", rtos.meminfo("lua"))
    end
end

-- wifi的STA相关事件
sys.subscribe("WLAN_STA_INC", wifi_sta_func)

-- 运行这个task的处理函数rtmp_task
sys.taskInitEx(rtmp_task, RTMP_TASK_NAME)

-- 启动内存检查任务
sys.taskInit(memory_check)
