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
local Posturl = "http://video.luatos.com:10030/api-system/deviceVideo/get"
local PostBody = {
    deviceAccess = "8",     -- 8 代表接入方式为RTMP
    deviceUser = "admin",   -- 平台录像机设置的设备用户（不是登录用的用户名）
    devicePsd = "Air123456" -- 平台录像机设置的设备密码（不是登录用的密码）
}

local rtmpurl = ""                   -- RTMP推流地址
local got_rtmp_url = false           -- 是否已经获取过RTMP地址

-- RTMP状态回调函数
local function rtmp_state_callback(state, ...)
    -- 打印RTMP状态变化基础日志
    log.info("rtmp状态变化", state, ...)

    -- 根据不同状态执行对应逻辑
    if state == "connected" then
        log.info("rtmp状态变化", "已连接到推流服务器")
    elseif state == "publishing" then
        log.info("rtmp状态变化", "已开始推流")
    elseif state == "error" or state == "disconnected" then
        log.info("rtmp状态变化", "出错:", ...)
        -- 发生错误时需要重试
        sys.publish("RTMP_ERROR")
    end
end

local function rtmp_task()
    while true do
        -- 1. 判断网卡是否准备就绪
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

        -- 2. HTTP请求获取RTMP服务器地址
        if not got_rtmp_url then
            local rtos_bsp = rtos.bsp()
            local GetDeviceid = ""
            if rtos_bsp == "Air8101" then
                GetDeviceid = netdrv.mac(socket.LWIP_STA) -- Air8101用STA MAC作为设备ID
            else
                GetDeviceid = mobile.imei()               -- 其他平台用IMEI作为设备ID
            end
            log.info("打印设备的ID号", GetDeviceid)

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

            if code ~= 200 then
                log.error("HTTP请求失败，5秒后重试")
                sys.wait(5000)
                goto CONTINUE_LOOP
            end

            log.info("打印的请求body", body)
            local JSONbody = json.decode(body)
            if not JSONbody or JSONbody.code ~= 200 then
                log.error("请求视频URL失败", JSONbody and JSONbody.msg or "未知错误")
                sys.wait(5000)
                goto CONTINUE_LOOP
            end

            rtmpurl = JSONbody.data.urlList[1]
            log.info("请求得到的RTMP地址", rtmpurl)
            if not rtmpurl then
                log.error("未获取到RTMP地址，5秒后重试")
                sys.wait(5000)
                goto CONTINUE_LOOP
            end
            got_rtmp_url = true
        end

        -- 3. 配置并打开摄像头
        local init_ok = excamera.open({
            id = camera.USB,
            sensor_width = 1280,
            sensor_height = 720,
            usb_port = 1,
            fps = 15,
            h264_qp_init = 40,
            h264_qp_i_max = 40,
            h264_qp_p_max = 25,
            h264_imb_bits = 8,
            h264_pmb_bits = 4,
            h264_pframe_nums = 29
        })

        if not init_ok then
            log.error("摄像头初始化失败，5秒后重试")
            sys.wait(5000)
            -- rtos.reboot() -- 重启
            goto CONTINUE_LOOP
        end

        -- 4. RTMP推流
        ::RTMP_PROC::
        local rtmp_ok = excamera.rtmp(rtmpurl, rtmp_state_callback)
        if not rtmp_ok then
            log.error("启动RTMP推流失败")
            excamera.close()
            sys.wait(5000)
            goto CONTINUE_LOOP
        end

        -- 5. 推流过程中监控内存状态
        local rtmp_error = false
        for i = 1, 60 do    -- 30秒 * 60 = 30分钟
            sys.wait(30000) -- 每30秒打印一次内存
            log.info("lua", rtos.meminfo())
            log.info("sys", rtos.meminfo("sys"))
            log.info("psram", rtos.meminfo("psram"))

            -- 检查是否有RTMP错误
            if sys.waitUntil("RTMP_ERROR", 100) then
                rtmp_error = true
                break
            end
        end

        -- 6. 关闭摄像头
        excamera.close()

        -- 7. 5秒后重试异常情况
        if rtmp_error then
            log.error("RTMP推流异常，5秒后重试")
            sys.wait(5000)
        end

        ::CONTINUE_LOOP::
    end
end

sys.taskInit(rtmp_task)
