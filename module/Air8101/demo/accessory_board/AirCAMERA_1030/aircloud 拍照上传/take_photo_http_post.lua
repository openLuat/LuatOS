--[[
@module  take_photo_http_post
@summary AirCAMERA_1030 USB摄像头拍照上传应用模块
@version 1.0
@date    2025.11.09
@author  陈取德
@usage
本demo主要使用AirCAMERA_1030 USB摄像头完成一次拍照上传任务
]] -- 摄像头拍照模块
-- 功能：提供摄像头初始化、拍照和资源管理功能
-- 引入excamera扩展库模块
local excamera = require "excamera"
-- 引入httpplus扩展库模块
local httpplus = require "httpplus"
-- 引入excloud库
local excloud = require("excloud")

-- 定义照片保存方式，有三种类型：
-- 1、ZBUFF保存，输入"ZBUFF"即可，excamera库会自动处理ZBUFF
-- 2、保存到内存文件系统中，路径名需指向/ram/文件夹
-- 3、保存到内置FLASH文件系统中
-- 选择其中一个即可，注释另两个路径变量
-- local save_method = "ZBUFF"
local save_method = "/ram/test.jpg"
-- local save_method = "/test.jpg"

-- USB摄像头支持多摄像头轮切拍摄
-- 该变量表示有多少路摄像头，如果有多路摄像头则会逐个轮切拍摄，顺序以HUB的USB端口号顺序
-- 如果只是一路摄像头，此处填1即可
local usb_port_num = 1

-- 拍照功能函数
-- 作用：循环监听拍照事件，执行摄像头初始化、拍照和资源释放
local function capture_func()
    -- 定义变量用于存储操作结果和数据
    local result, data
    -- 无限循环，持续等待拍照事件
    while true do
        -- 等待外部触发拍照事件(ONCE_CAPTURE)
        local result, usb_port = sys.waitUntil("ONCE_CAPTURE")
        -- 配置USB摄像头参数表
        local usb_camera_param = {
            id = camera.USB, -- 摄像头类型，USB接口
            sensor_width = 1280, -- 摄像头像素宽度，1280像素
            sensor_height = 720, -- 摄像头像素高度，720像素
            usb_port = usb_port,
            save_path = save_method -- 照片保存路径，保存在RAM中
        }
        -- 初始化摄像头，传入配置参数
        result = excamera.open(usb_camera_param)
        -- 记录摄像头初始化状态
        log.info("初始化状态", result,"这是第"..usb_camera_param.usb_port.."个摄像头")
        -- 判断摄像头初始化是否成功，不成功则直接关闭，成功则启动拍照
        if result then
            -- 执行拍照操作
            result, data = excamera.photo()
            -- 拍照执行完成则上传，否则关闭摄像头
            if result then
                log.info("这是第"..usb_port.."个摄像头拍的")
                log.info("照片存储路径", save_method)
                
                -- 检查文件是否存在
                if io.exists(save_method) then
                    log.info("文件存在，大小:", io.fileSize(save_method))
                else
                    log.warn("文件不存在，拍照后立即检查")
                end
                
                -- 通过网卡状态判断WIFI是否连接成功，WIFI连接成功后再运行照片上传任务。
                while not socket.adapter(socket.dft()) do
                    -- 在此处阻塞等待WIFI连接成功的消息"IP_READY"，避免联网过快，丢失了"IP_READY"信息而导致一直被卡住。
                    -- 或者等待30秒超时退出阻塞等待状态
                    log.warn("tcp_client_main_task_func", "wait IP_READY")
                    sys.waitUntil("IP_READY", 30000)
                end
                if type(data) == "userdata" then
                    data = data:query()
                else
                    data = io.readFile(data)
                end
                -- 拍照完成后触发上传事件
                sys.publish("PHOTO_READY", save_method)
            end
        end
        -- 关闭摄像头，释放资源
        excamera.close()
    end
end


function excloud_task_func()
    -- -- 配置excloud参数
    local ok, err_msg = excloud.setup({
        use_getip = true, -- 使用getip服务
        device_type = 2,   -- WIFI设备
        auth_key = "jqDKVo10JaU82v9h5sEprAWDfdwQEgMa", -- 项目key，根据实际修改
        transport = "tcp",       -- 使用TCP传输
        auto_reconnect = true,   -- 自动重连
        reconnect_interval = 10, -- 重连间隔(秒)
        max_reconnect = 5,       -- 最大重连次数
        mtn_log_enabled = true,  -- 启用运维日志
        mtn_log_blocks = 1,      -- 日志文件块数
        mtn_log_write_way = excloud.MTN_LOG_CACHE_WRITE  -- 缓存写入方式
    })

    if not ok then
        log.info("初始化失败: " .. err_msg)
        return
    end
    log.info("excloud初始化成功")

    -- 开启excloud服务
    local ok, err_msg = excloud.open()
    if not ok then
        log.info("开启excloud服务失败: " .. err_msg)
        return
    end
    log.info("excloud服务已开启")
    -- 启动自动心跳，默认5分钟一次的心跳
    excloud.start_heartbeat()
    log.info("自动心跳已启动")

    sys.waitUntil("aircloud_connected", 10000)
    
    -- 循环监听拍照完成事件并上传
    while true do
        local result, photo_path = sys.waitUntil("PHOTO_READY")
        if result then
            -- 上传图片
            log.info("开始上传图片")
            if not excloud.status().is_connected then
                log.info("设备未连接，跳过图片上传")
                -- 删除文件
                if save_method ~= "ZBUFF" then
                    os.remove(save_method)
                end
                return
            end
            if io.exists(save_method) then
                local ok, err = excloud.upload_image(save_method, "test.jpg")
                if ok then
                    log.info("图片上传成功")
                else
                    log.error("图片上传失败:", err)
                end
                -- 上传完成后删除文件
                if save_method ~= "ZBUFF" then
                    os.remove(save_method)
                end
            else
                log.warn("测试图片文件不存在")
            end
        end
    end
end

-- 内存检查函数
-- 作用：定期监控系统内存使用情况
local function memory_check()
    -- 无限循环，定期检查内存
    while true do
        -- 等待10秒
        sys.wait(10000)
        -- 打印系统内存使用信息
        log.info("sys ram", rtos.meminfo("sys"))
        -- 打印Lua虚拟机内存使用信息
        log.info("lua ram", rtos.meminfo("lua"))
    end
end

-- AirCAMERA_1030 DEMO应用触发函数，每30S触发一次拍照
local function AirCAMERA_1030_func()
    while true do
        -- 循环推送USB端口号，触发轮切拍照功能
        for i = 1, usb_port_num do
            sys.publish("ONCE_CAPTURE",i)
            sys.wait(10000)
        end
    end
end

-- 创建上传照片到aircloud平台任务
-- 作用：在单独的任务中运行上传照片到aircloud平台逻辑
sys.taskInit(excloud_task_func)

-- 创建拍照功能任务
-- 作用：在单独的任务中运行拍照逻辑
sys.taskInit(capture_func)

-- 创建内存监控任务
-- 作用：在单独的任务中运行内存监控逻辑
sys.taskInit(memory_check)

-- 创建拍照触发任务
-- 作用：每30秒触发一次拍照上传业务
sys.taskInit(AirCAMERA_1030_func)
