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


local Posturl = "http://video.luatos.com:10030/api-system/deviceVideo/get"
local PostBody = {
    deviceAccess = "8",     -- 8 代表接入方式为RTMP
    deviceUser = "admin",   -- 平台录像机设置的设备用户（不是登录用的用户名）
    devicePsd = "Air123456" -- 平台录像机设置的设备密码（不是登录用的密码）
}

-- 配置摄像头初始化参数
local usb_camera_table = {
    id = camera.USB,
    sensor_width = 1280,
    sensor_height = 720,
    usb_port = 1
}

local rtmpc = nil  -- 重连控制变量与方法
local rtmp_reconnecting = false -- 是否正在重连
local rtmp_retries = 0          -- 当前重连次数

-- rtmp出现问题时的重连逻辑
local function rtmp_try_reconnect()
    while true do
        sys.waitUntil("RECONNECT_RTMP")
        if rtmp_reconnecting or not rtmpc then return end
        rtmp_reconnecting = true
        rtmpc:disconnect() -- 确认断开当前连接
        while rtmp_reconnecting do
            rtmp_retries = rtmp_retries + 1
            local isNetReady, adapterIndex = socket.adapter()
            log.info("rtmp", "reconnect attempt", rtmp_retries, "adapter_index: ", adapterIndex)
            -- 检测当前网络是否就绪
            if isNetReady then
                local ok = rtmpc:connect()
                if ok then
                    -- 等待短时间以便连接完成
                    sys.wait(1000)
                    local st = rtmpc:getState()
                    if st == rtmp.STATE_CONNECTED or st == rtmp.STATE_PUBLISHING then
                        log.info("rtmp", "reconnect success")
                        -- 恢复推流
                        rtmpc:start()
                        rtmp_reconnecting = false
                        rtmp_retries = 0
                    end
                end
            else
                -- 等待任意网卡变为就绪
                log.info("rtmp", "waiting for IP_READY")
                sys.waitUntil("IP_READY", 60 * 1000)
            end
            sys.wait(60 * 1000) -- 每次重连间隔60秒
        end
    end
end

local function state_changed(state, ...)
    -- 打印RTMP状态变化基础日志
    log.info("rtmp状态变化", state, ...)
    
    -- 根据不同状态执行对应逻辑
    if state == rtmp.STATE_CONNECTED then
        log.info("rtmp状态变化", "已连接到推流服务器")
        rtmp_retries = 0  -- 重置重连次数
    elseif state == rtmp.STATE_PUBLISHING then
        log.info("rtmp状态变化", "已开始推流")
        rtmp_retries = 0  -- 重置重连次数
    elseif state == rtmp.STATE_ERROR or state == rtmp.STATE_IDLE then
        log.info("rtmp状态变化", "出错:", ...)
        -- 发生错误时发布重连消息（若网络可用则立即尝试）
        sys.publish("RECONNECT_RTMP", ...)
    end
end

local function rtmp_task()
    --  打印版本信息
    log.info("当前脚本版本号：", VERSION, "core版本号：", rtos.version())

    -- 如果当前时间点设置的默认网卡还没有连接成功，一直在这里循环等待
    while not socket.adapter(socket.dft()) do
        log.warn("wait IP_READY", socket.dft())
        -- 在此处阻塞等待默认网卡连接成功的消息"IP_READY"
        -- 或者等待1秒超时退出阻塞等待状态;
        -- 注意：此处的1000毫秒超时不要修改的更长；
        -- 因为当使用exnetif.set_priority_order配置多个网卡连接外网的优先级时，会隐式的修改默认使用的网卡
        -- 当exnetif.set_priority_order的调用时序和此处的socket.adapter(socket.dft())判断时序有可能不匹配
        -- 此处的1秒，能够保证，即使时序不匹配，也能1秒钟退出阻塞状态，再去判断socket.adapter(socket.dft())
        sys.waitUntil("IP_READY", 1000)
    end

    local rtos_bsp = rtos.bsp()
    local GetDeviceid = ""
    if rtos_bsp == "Air8101" then
        GetDeviceid = netdrv.mac(socket.LWIP_STA) -- Air8101用STA MAC作为设备ID
    else
        GetDeviceid = mobile.imei()               -- 其他平台用IMEI作为设备ID
    end
    log.info("打印设备的ID号", GetDeviceid)

    -- 4. 构造URL并发送POST请求获取RTMP推流地址
    local URL = Posturl .. "/" .. GetDeviceid
    log.info("打印的URL", URL)
    local Camera_header = {
        ["Accept-Encoding"] = "identity",
        ["Host"] = "video.luatos.com:10030",
        ["Content-Type"] = "application/json"
    }
    -- 发送POST请求并等待响应
    local code, headers, body = http.request("POST", URL, Camera_header, json.encode(PostBody)).wait()
    log.info("打印的请求code", code)
    if code == 200 then
        log.info("打印的请求body", body)
        local JSONbody = json.decode(body)
        if JSONbody.code ~= 200 then
            log.info("请求视频URL失败", JSONbody.msg)
            return -- 请求失败则退出函数
        end
        rtmpurl = JSONbody.data.urlList[1]
        log.info("请求得到的RTMP地址", rtmpurl)
    end

    -- 配置摄像头参数（H264编码相关）
    camera.config(0, camera.CONF_UVC_FPS, 15)
    camera.config(0, camera.CONF_H264_QP_INIT, 40)
    camera.config(0, camera.CONF_H264_QP_I_MAX, 40)
    camera.config(0, camera.CONF_H264_QP_P_MAX, 25)
    camera.config(0, camera.CONF_H264_IMB_BITS, 8)
    camera.config(0, camera.CONF_H264_PMB_BITS, 4)
    camera.config(0, camera.CONF_H264_PFRAME_NUMS, 29)

    -- 摄像头初始化
    socket.sntp()
    result = camera.init(usb_camera_table)
    log.info("摄像头初始化", result)
    if result ~= 0 then
        log.info("摄像头初始化失败, 5秒后重启设备, 进行重试")
        sys.wait(5000)
        rtos.reboot() -- 初始化失败则重启设备
    end
    camera.start(camera.USB) -- 启动摄像头

    -- 创建RTMP客户端并连接推流服务器
    if not rtmpc then
        rtmpc = rtmp.create(rtmpurl) 
    end
    rtmpc:setCallback(state_changed) -- 注册状态回调
    log.info("开始连接到推流服务器...")
    sys.wait(5000) 
    rtmpc:connect() -- 连接RTMP服务器

    log.info("rtmp", "开始推流...")
    rtmpc:start() -- 自动触发摄像头采集并推流

    -- 循环打印内存状态
    while 1 do
        sys.wait(30 * 1000) -- 每30秒打印一次
        log.info("lua", rtos.meminfo())
        log.info("sys", rtos.meminfo("sys"))
        log.info("psram", rtos.meminfo("psram"))
    end
end

sys.taskInit(rtmp_task)

sys.taskInit(rtmp_try_reconnect)
