--[[
@module  video_http_post
@summary 单摄像头循环录制视频上传功能模块
@version 1.0
@date    2026.01.15
@author  王城钧
@usage
本文件为单摄像头循环录制视频上传功能模块，核心业务逻辑为：
1. DVP 摄像头初始化与视频采集
2. 摄像头视频 MP4 格式录制与SD卡文件保存
3. 将拍摄的视频通过httpplus上传到对应服务器
]]

-- 引入excamera库
local excamera = require("excamera")
-- 引入httpplus库
local httpplus = require("httpplus")

-- TF卡挂载函数
local function mount_tf_card()
    -- gpio13为8101 TF卡的供电控制引脚，在挂载前需要设置为高电平
    gpio.setup(13, 1, gpio.PULLUP)

    local ret = fatfs.mount(fatfs.SDIO, "/sd")
    if ret then
        log.info("TF卡挂载成功")
        -- 检查空间
        local free_info = fatfs.getfree("/sd")
        if free_info then
            log.info("剩余空间:", free_info.free_kb / 1024, "MB")
        end
        return true
    else
        log.error("TF卡挂载失败")
        return false
    end
end

-- 视频录制功能函数
local function video_capture_func()
    -- 打开控制camera的LDO
    gpio.setup(28, 1, gpio.PULLUP)
    -- 设置记录第几个视频的变量
    local n = 0
    while true do
        -- 等待外部触发录制事件
        sys.waitUntil("ONCE_RECORD")
        -- 配置dvp摄像头参数表
        local dvp_camera_param = {
            id = camera.DVP,     -- 摄像头类型，USB接口
            sensor_width = 1280, -- 摄像头像素宽度，1280像素
            sensor_height = 720  -- 摄像头像素高度，720像素
        }

        -- 初始化摄像头，传入配置参数
        local result = excamera.open(dvp_camera_param)
        -- 记录摄像头初始化状态
        log.info("摄像头初始化状态", result)
        if result then
            -- 视频编号递增
            n = n + 1
            local filepath = "/sd/video_dvp_ " .. n .. ".mp4"

            -- 录制视频：文件路径、时长(ms)
            log.info("开始录制视频", filepath)
            local success = excamera.video(filepath, 30000) -- 录制30秒视频

            -- 关闭摄像头，释放资源
            excamera.close()

            if success then
                log.info("视频录制成功!")

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

                -- 创建上传选项
                local opts = {
                    url = "http://upload.air32.cn/api/upload/mp4",
                    method = "POST",
                    bodyfile = filepath,
                    timeout = 150
                }
                -- 执行上传并处理结果
                local code = httpplus.request(opts)

                if code == 200 then
                    log.info("http上传完成，code:", code)
                    log.info("上传成功")
                else
                    log.info("上传失败，code:", code)
                end
            else
                log.error("视频录制失败!")
            end
            -- 当项目不再需要保存此视频文件时，可以参考下面一行代码，在合适的位置删除视频文件
            os.remove(filepath)
        else
            log.error("摄像头初始化失败!")
        end
    end
end

-- AirCAMERA_1020 DEMO应用触发函数，每30S触发一次视频录制
local function AirCAMERA_1020_func()
    while true do
        sys.publish("ONCE_RECORD")
        sys.wait(30000)
    end
end

-- 内存检查函数
local function memory_check()
    while true do
        -- 等待10秒
        sys.wait(10000)
        -- 打印系统内存使用信息
        log.info("系统内存使用情况", rtos.meminfo("sys"))
        -- 打印Lua虚拟机内存使用信息
        log.info("Lua虚拟机内存使用情况", rtos.meminfo("lua"))
    end
end

-- 挂载TF卡任务
sys.taskInit(mount_tf_card)

-- 视频录制任务
sys.taskInit(video_capture_func)

-- 视频录制触发任务
sys.taskInit(AirCAMERA_1020_func)

-- 内存检查任务
sys.taskInit(memory_check)
