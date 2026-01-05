-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "dvp_cam_rtmp"
VERSION = "1.0.3"

local fota_enable = false  -- 是否启用FOTA功能
local fota_looptime = 4*3600000  -- FOTA轮询时间，默认4小时

if fota_enable then
    -- 使用合宙iot平台时需要这个参数  客户如果使用请记得修改成自己的项目key
    PRODUCT_KEY = "6XtIwnc4GRfJtcgFQqtwn0U9XnERfAgR"        -- DVP摄像头推流的项目KEY

    libfota2 = require "libfota2"
end

local Posturl = "http://video.luatos.com:10030/api-system/deviceVideo/get"
local PostBody = {
    deviceAccess = "8",         -- 8 代表接入方式为RTMP
    deviceUser = "admin",       -- 平台录像机设置的设备用户（不是登录用的用户名）
    devicePsd = "Air123456"     -- 平台录像机设置的设备密码（不是登录用的密码）
}

local wifi_ssid = "admin-降功耗，找合宙！"
local wifi_password = "Air123456"

local camera_id = camera.DVP
local dvp_camera_table = {
    id = camera_id,
    sensor_width = 1280,
    sensor_height = 720
}

local rtmpc = nil
-- 重连控制变量与方法
local rtmp_reconnecting = false -- 是否正在重连
local rtmp_retries = 0         -- 当前重连次数
local rtmp_max_retries = 5     -- 最大重连次数

-- rtmp出现问题时的重连逻辑
function rtmp_try_reconnect()
    while true do
        local ret, error_id = sys.waitUntil("RECONNECT_RTMP")
        if rtmp_reconnecting or not rtmpc then return end
        -- if error_id > -4 and error_id ~= -1 then
        --     -- 非重连就能解决的错误，不进行重连
        --     log.info("rtmp", "error is not recoverable, will not reconnect", error_id)
        --     return
        -- end
        rtmp_reconnecting = true
        rtmpc:disconnect()  -- 确认断开当前连接
        while rtmp_retries < rtmp_max_retries do
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
                        return
                    end
                end
            else
                -- 等待任意网卡变为就绪
                log.info("rtmp", "waiting for IP_READY")
                sys.waitUntil("IP_READY", 60000)
            end
            sys.wait(10000) -- 每次重连间隔10秒
        end
        log.info("rtmp", "reconnect failed after ... ", rtmp_retries)
        rtmp_reconnecting = false
    end
end

if fota_enable then
    -- 升级结果的回调函数
    local function fota_cb(ret)
        log.info("fota result: ", ret)
        if ret == 0 then
            rtos.reboot()
        end
    end

    local ota_opts = {}
    -- 定时自动升级
    sys.timerLoopStart(libfota2.request, fota_looptime, fota_cb, ota_opts)
end

sys.taskInit(function()
    sys.wait(1000)
    log.info("当前脚本版本号：", VERSION, "core版本号：", rtos.version())
    wlan.init()
    wlan.connect(wifi_ssid, wifi_password, 1)

    sys.waitUntil("IP_READY")
    socket.sntp()

    local rtos_bsp = rtos.bsp()
    local GetDeviceid = ""
    if rtos_bsp == "Air8101" or rtos_bsp == "Air8201" then
        GetDeviceid = netdrv.mac(socket.LWIP_STA)   -- 使用STA_MAC作为设备ID
    else
        GetDeviceid = mobile.imei()                 -- 使用IMEI作为设备ID
    end
    log.info("打印设备的ID号",GetDeviceid)--3030170932
    local URL = Posturl.."/"..GetDeviceid
    log.info("打印的URL",URL)
    local Camera_header = {["Accept-Encoding"]="identity",["Host"]="video.luatos.com:10030",["Content-Type"] = "application/json"}
    local code,headers,body = http.request("POST", URL,Camera_header,json.encode(PostBody)).wait()
    log.info("打印的请求code",code)
    if code == 200 then
        log.info("打印的请求body",body)
        local JSONbody = json.decode(body)
        if JSONbody.code ~= 200 then
            log.info("请求视频URL失败", JSONbody.msg)
            return
        end
        rtmpurl = JSONbody.data.urlList[1]
        log.info("请求得到的RTMP地址",rtmpurl)
    end

    camera.config(0, camera.CONF_UVC_FPS, 15)
    -- camera.config(0, camera.CONF_H264_QP_INIT, 12)
    -- camera.config(0, camera.CONF_H264_IMB_BITS, 120)
    camera.config(0, camera.CONF_H264_PMB_BITS, 20)
    camera.config(0, camera.CONF_H264_PFRAME_NUMS, 23)
    socket.sntp()
    sys.wait(200)
    result = camera.init(dvp_camera_table)
    log.info("摄像头初始化", result)
    camera.start(camera_id)

    if not rtmpc then
        rtmpc = rtmp.create(rtmpurl)
    end

    rtmpc:setCallback(function(state, ...)
        log.info("rtmp状态变化", state, ...)
        if state == rtmp.STATE_CONNECTED then
            log.info("rtmp状态变化", "已连接到推流服务器")
            rtmp_retries = 0
        elseif state == rtmp.STATE_PUBLISHING then
            log.info("rtmp状态变化", "已开始推流")
            rtmp_retries = 0
        elseif state == rtmp.STATE_ERROR then
            log.info("rtmp状态变化", "出错:", ...)
            -- 发生错误时尝试重连（若网络可用则立即尝试）
            sys.publish("RECONNECT_RTMP", ...)
        end
    end)
    log.info("开始连接到推流服务器...")
    sys.wait(100)
    rtmpc:connect()
    sys.wait(300)

    -- 开始处理
    log.info("rtmp", "开始推流...")
    rtmpc:start() -- 已自动调用 camera.capture(camera_id, "rtmp", 1)
    
    while 1 do
        --- 打印一下内存状态
        sys.wait(10*1000)
        log.info("lua", rtos.meminfo())
        log.info("sys", rtos.meminfo("sys"))
        log.info("psram", rtos.meminfo("psram"))
        sys.wait(2000)
    end
    -- #################################################

end)

sys.taskInit(rtmp_try_reconnect)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
