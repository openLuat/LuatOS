-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "usb_cam_rtmp"
VERSION = "1.0.2"

local fota_enable = false  -- 是否启用FOTA功能

if fota_enable then
    local fota_looptime = 4*3600000  -- FOTA轮询时间，默认4小时

    -- 使用合宙iot平台时需要这个参数  客户如果使用请记得修改成自己的项目key
    PRODUCT_KEY = "8Ram1dVPp1QPfuaHoJ6xuk5qFrBxoNRu"        -- USB摄像头推流的项目KEY

    libfota2 = require "libfota2"
end

local camera_id = camera.USB

local usb_camera_table = {
    id = camera_id,
    sensor_width = 1280,
    sensor_height = 720,
    usb_port = 1
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
    gpio.setup(28, 1, gpio.PULLUP)
    log.info("当前脚本版本号：", VERSION, "core版本号：", rtos.version())
    wlan.init()
    wlan.connect("luatos1234", "12341234", 1)

    sys.waitUntil("IP_READY")

    camera.config(0, camera.CONF_UVC_FPS, 15)
    camera.config(0, camera.CONF_H264_QP_INIT, 40)
    camera.config(0, camera.CONF_H264_QP_I_MAX, 40)
    camera.config(0, camera.CONF_H264_QP_P_MAX, 25)
    camera.config(0, camera.CONF_H264_IMB_BITS, 8)
    camera.config(0, camera.CONF_H264_PMB_BITS, 4)
    camera.config(0, camera.CONF_H264_PFRAME_NUMS, 29)
    socket.sntp()
    sys.wait(200)
    result = camera.init(usb_camera_table)
    log.info("摄像头初始化", result)
    camera.start(camera_id)

    if not rtmpc then
        -- rtmpc = rtmp.create("rtmp://192.168.1.10:1935/live/abc")
        rtmpc = rtmp.create("rtmp://180.152.6.34:1935/stream1live/1ca786f5_23e5_4d89_8b1d_2eec6932775a_0001")
        -- rtmpc = rtmp.create("rtmp://47.94.236.172/live/1ca786f5") -- 替换为你的推流地址
        -- rtmpc = rtmp.create("rtmp://180.152.6.34:1936/live/guangzhou")
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
        sys.wait(30*1000)
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
