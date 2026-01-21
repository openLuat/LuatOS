PROJECT = "camerademo"
VERSION = "1.0.0"
sys = require("sys")
httpplus = require "httpplus"

-- 本demo适用于Air8101核心板 + AirCAMERA_1020摄像头配件板

-- 演示摄像头拍照，将图片数据存在zbuff中
-- 通过http post将拍照文件上传至upload.air32.cn，数据访问页面是 https://www.air32.cn/upload/data/

-- IO电平设置到3.0~3.1v
pm.ioVol(pm.IOVOL_ALL_GPIO, 3100)

-- WIFI热点名称
local ssid = "luatos1234"
-- WIFI热点密码
local password = "12341234"

local camera_id = camera.DVP

local dvp_camera_table = {
    id = camera_id,
    sensor_width = 1600,
    sensor_height = 1200
}

-- 摄像头回调
camera.on(camera_id, "scanned", function(id, str)
    if type(str) == 'string' then
        log.info("扫码结果", str)
    elseif str == false then
        log.error("摄像头没有数据")
    else
        log.info("摄像头数据", str)
        sys.publish("capture_done")
    end
end)

local rawbuff, err

sys.taskInit(function()
    local result
    -- 初始化WIFI
    wlan.init()
    -- 连接WIFI
    wlan.connect(ssid, password)

    while true do
        -- 等待网络就绪消息，超时时间30秒
        result = sys.waitUntil("IP_READY", 30000)
        if result then
            log.info("网络已就绪", result)
            break
        end
        log.info("等待网络就绪超时")
    end

    rawbuff = zbuff.create(200 * 1024, 0, zbuff.HEAP_PSRAM)
    if rawbuff == nil then
        log.info("zbuff创建失败", err)
        while true do
            sys.wait(1000)
        end
    end
    -- 初始化摄像头
    camera.init(dvp_camera_table)
    while 1 do
        -- camera.init(dvp_camera_table)
        -- 启动摄像头
        camera.start(camera_id)
        camera.capture(camera_id, rawbuff, 1)
        result, param = sys.waitUntil("capture_done", 30000)
        camera.stop(camera_id)
        -- 完全关闭摄像头才用这个
        -- camera.close(camera_id)
        if result then
            log.info("拍照成功")
            local code, resp = httpplus.request({
                url = "http://upload.air32.cn/api/upload/jpg",
                method = "POST",
                body = rawbuff
            })
            log.info("http", code, resp)
            if code == 200 then
                log.info("上传成功")
            else
                log.info("上传失败")
            end
        else
            log.info("拍照失败")
        end
        rawbuff:resize(200 * 1024)
        -- 等待30秒
        sys.wait(30000)
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
