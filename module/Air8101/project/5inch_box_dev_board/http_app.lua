local httpplus = require "httpplus"
--加载AirCAMERA_1030驱动文件
local air_camera = require "AirCAMERA_1030"

--打开AirCAMERA_1030摄像头
--拍摄一张1280*720分辨率的照片，通过http上传到服务器；
--上传结束后，等待10秒钟重复执行拍照和上传的动作；
local function http_upload_photo_task_func() 

    --打开摄像头
    local result = air_camera.open()
    --如果打开失败，直接退出这个函数
    if not result then
        log.error("http_upload_photo_task_func error", "air_camera.open fail")
        return
    end

    --拍摄一张1280*720分辨率的照片，通过http上传到服务器；
    --上传结束后，等待10秒钟重复执行拍照和上传的动作；
    while true do

        --拍摄一张1280*720分辨率的照片
        --如果拍摄成功，result中存储是照片数据
        --如果拍摄失败，result为false
        result = air_camera.capture()
        --如果拍摄失败，关闭摄像头，并且直接退出这个函数
        if not result then
            log.error("http_upload_photo_task_func error", "air_camera.capture fail")
            air_camera.close()
            return
        end

        --检查WIFI连接状态
        log.info("http_upload_photo_task_func", "socket.adapter(socket.LWIP_STA)", socket.adapter(socket.LWIP_STA))
        --如果WIFI还没有连接成功
        if not socket.adapter(socket.LWIP_STA) then
            --在此处阻塞等待WIFI连接成功的消息"IP_READY"
            --或者等待30秒超时退出阻塞等待状态
            --如果没有等到"IP_READY"消息，关闭摄像头，并且直接退出这个函数
            if not sys.waitUntil("IP_READY", 30000) then
                log.error("http_upload_photo_task_func error", "ip network timeout")
                air_camera.close()
                return
            end
        end

        -- 通过WIFI网络将拍摄到的照片数据result上传到服务器upload.air32.cn
        -- 如果上传成功，电脑上浏览器打开https://www.air32.cn/upload/data/jpg/，打开对应的测试日期目录，点击具体的测试时间照片，可以查看摄像头拍照上传的照片
        -- 执行httpplus.request后，等待服务器的http应答，此处会阻塞当前task，等待整个过程成功结束或者出现错误异常结束
        -- code表示结果，number类型，详细说明参考API手册，一般来说：
        --             200表示成功
        --             小于0的值表示出错，例如-8表示超时错误
        --             其余结果值参考API手册
        local code = httpplus.request({
            url = "http://upload.air32.cn/api/upload/jpg",
            method = "POST",
            body = result
        })
        log.info("http_upload_photo_task_func", "httpplus.request", code)

        -- 打印内存信息, 调试用
        log.info("sys", rtos.meminfo())
        log.info("sys", rtos.meminfo("sys"))
        log.info("psram", rtos.meminfo("psram"))

        -- 等待10秒钟
        sys.wait(10000)
    end

    --关闭摄像头
    air_camera.close()
end

--创建并且启动一个task
--运行这个task的主体函数http_upload_photo_task_func
sys.taskInit(http_upload_photo_task_func)
