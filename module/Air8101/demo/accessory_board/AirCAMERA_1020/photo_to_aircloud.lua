--[[
@module  take_photo_http_post
@summary AirCAMERA_1020 DVP摄像头拍照上传应用模块
@version 1.0
@date    2025.11.09
@author  陈取德
@usage
本demo主要使用AirCAMERA_1020 DVP摄像头完成一次拍照上传任务
]] -- 摄像头拍照模块
-- 功能：提供摄像头初始化、拍照和资源管理功能
-- 引入excamera扩展库模块
local excamera = require "excamera"
-- 引入httpplus扩展库模块
local httpplus = require "httpplus"
-- 导入excloud库
local excloud = require "excloud"
-- 配置excloud参数
local project_auth_key = "sh5g0OTP7ThOSlGKmE5jiEMbOBqQWyw9"

-- 定义照片保存方式，有三种类型：
-- 1、ZBUFF保存，输入"ZBUFF"即可，excamera库会自动处理ZBUFF
-- 2、保存到内存文件系统中，路径名需指向/ram/文件夹
-- 3、保存到内置FLASH文件系统中
-- 选择其中一个即可，注释另两个路径变量
local save_method = "ZBUFF"
-- local save_method = "/ram/test.jpg"
-- local save_method = "/test.jpg"

--[[
excloud事件回调函数
参数：
    event: 事件类型字符串
    data: 事件数据，根据事件类型不同而不同

事件类型说明：
    connect_result: 连接结果
    auth_result: 认证结果
    disconnect: 断开连接
    reconnect_failed: 重连失败
]]
function on_excloud_event(event, data)
    -- 打印事件信息
    log.info("用户回调函数", event, json.encode(data))
    -- 处理连接结果事件
    if event == "connect_result" then
        if data.success then
            log.info("连接成功")
            -- 发布连接成功消息，通知其他任务
            sys.publish("aircloud_connected")
        else
            log.info("连接失败: " .. (data.error or "未知错误"))
        end
        -- 处理认证结果事件
    elseif event == "auth_result" then
        if data.success then
            log.info("认证成功")
        else
            log.info("认证失败: " .. data.message)
        end
        -- 处理断开连接事件
    elseif event == "disconnect" then
        log.warn("与服务器断开连接")
        -- 处理重连失败事件
    elseif event == "reconnect_failed" then
        log.info("重连失败，已尝试 " .. data.count .. " 次")
    end
end

-- 注册excloud事件回调函数
excloud.on(on_excloud_event)

--[[
excloud任务函数
功能：
    1. 等待网络连接就绪
    2. 配置excloud参数
    3. 初始化并开启excloud服务
    4. 启动自动心跳
]]
local function excloud_task_func()
    -- 如果当前时间点设置的默认网卡还没有连接成功，一直在这里循环等待
    while not socket.adapter(socket.dft()) do
        log.warn("excloud_task_func", "wait IP_READY", socket.dft())
        -- 在此处阻塞等待默认网卡连接成功的消息"IP_READY"
        -- 或者等待1秒超时退出阻塞等待状态;
        -- 注意：此处的1000毫秒超时不要修改的更长；
        -- 因为当使用exnetif.set_priority_order配置多个网卡连接外网的优先级时，会隐式的修改默认使用的网卡
        -- 当exnetif.set_priority_order的调用时序和此处的socket.adapter(socket.dft())判断时序有可能不匹配
        -- 此处的1秒，能够保证，即使时序不匹配，也能1秒钟退出阻塞状态，再去判断socket.adapter(socket.dft())
        sys.waitUntil("IP_READY", 1000)
    end

    -- 检查是否使用默认的示例key
    if project_auth_key == "123" or project_auth_key == "123456" then
        log.warn("photo_to_aircloud",
            "请改为自己的key，如不知道对应key的可以查看main.lua 54-57行的指导进行添加key的操作")
    end

    local ok, err_msg = excloud.setup({
        use_getip = true, -- 使用getip服务
        device_type = 2, -- WIFI设备
        auth_key = project_auth_key, -- 认证密钥
        transport = "tcp", -- 使用TCP传输
        auto_reconnect = true, -- 自动重连
        reconnect_interval = 10, -- 重连间隔(秒)
        max_reconnect = 5, -- 最大重连次数
        mtn_log_enabled = true, -- 启用运维日志
        mtn_log_blocks = 2, -- 日志文件块数
        mtn_log_write_way = excloud.MTN_LOG_CACHE_WRITE -- 缓存写入方式
    })

    -- 检查初始化是否成功
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
end

--[[
照片上传任务函数
功能：
    1. 等待excloud连接建立
    2. 等待图片数据
    3. 上传图片到云端
    4. 处理上传结果
]]
function upload_image_fun(image)
    if excloud.status().is_connected then
        log.info("开始上传图片")
        if image then
            local ok, err = excloud.upload_image(image, "test.jpg")
            if ok then
                log.info("图片上传成功")
                return true
            else
                log.error("图片上传失败:", err)
                return false
            end
        else
            log.warn("图片数据为空")
            return false
        end
    end
    log.info("excloud连接已断开，等待重连")
    return false
end

-- 拍照功能函数
-- 作用：循环监听拍照事件，执行摄像头初始化、拍照和资源释放
local function capture_func()
    -- 定义变量用于存储操作结果和数据
    local result, data, err
    -- 增加重试次数，最多重试5次，避免日志量过大
    local retry_count = 0
    -- 出现异常后重新初始化，最多重试5次
    while retry_count < 5 do
        -- 配置gc032a摄像头参数表
        local dvp_camera_param = {
            id = camera.DVP, -- 摄像头类型，DVP接口
            sensor_width = 1280, -- 摄像头像素宽度，1280像素
            sensor_height = 720, -- 摄像头像素高度，720像素
            save_path = save_method, -- 照片保存路径，保存在RAM中
            i2c_id = 1  -- 模块上使用的I2C编号
        }
        -- 初始化摄像头，传入配置参数
        result = excamera.open(dvp_camera_param)
        -- 记录摄像头初始化状态
        log.info("初始化状态", result)
        -- 判断摄像头初始化是否成功，不成功则直接关闭，成功则启动拍照
        -- 无限循环，持续等待拍照事件
        while result do
            -- 等待外部触发拍照事件(ONCE_CAPTURE)
            sys.waitUntil("ONCE_CAPTURE")
            -- 执行拍照操作
            result, data = excamera.photo()
            -- 拍照执行完成则上传，否则关闭摄像头
            if result then
                -- 通过网卡状态判断WIFI是否连接成功，WIFI连接成功后再运行照片上传任务。
                while not socket.adapter(socket.dft()) do
                    -- 在此处阻塞等待WIFI连接成功的消息"IP_READY"，避免联网过快，丢失了"IP_READY"信息而导致一直被卡住。
                    -- 或者等待30秒超时退出阻塞等待状态
                    log.warn("tcp_client_main_task_func", "wait IP_READY")
                    sys.waitUntil("IP_READY", 30000)
                end
                upload_image_fun(data)
            end
            -- 判断是否ZBUFF存储方式，如果是文件系统保存则删除本地文件
            if save_method ~= "ZBUFF" then
                os.remove(dvp_camera_param.save_path)
            end
        end
        -- 关闭摄像头，释放资源
        -- 使用ZBUFF存储方式时，close传入true后，excamera内部创建的ZBUFF会缩减至0字节，放出内存但是不释放ZBUFF，便于下次拍照时调用；
        -- 重复申请和释放ZBUFF会导致垃圾内存堆积，影响系统内存；
        excamera.close(true)
        -- 拍照出错，等待5秒，重试摄像头初始化
        sys.wait(5000)
        -- 重试次数增加
        retry_count = retry_count + 1
        log.info("retry_count", retry_count)
    end
    -- 重试5次后，提示用户检查摄像头连接或重启设备
    log.info("camera init failed, please check the camera connection or reboot, retry_count:", retry_count)
end

-- 内存检查函数
-- 作用：定期监控系统内存使用情况
local function memory_check()
    -- 无限循环，定期检查内存
    while true do
        -- 等待3秒
        sys.wait(3000)
        -- 打印系统内存使用信息
        log.info("sys ram", rtos.meminfo("sys"))
        -- 打印Lua虚拟机内存使用信息
        log.info("lua ram", rtos.meminfo("lua"))
    end
end

-- AirCAMERA_1040 DEMO应用触发函数，每30S触发一次拍照
local function AirCAMERA_1040_func()
    while true do
        sys.wait(30000)
        sys.publish("ONCE_CAPTURE")
    end
end

-- 启动excloud连接任务
sys.taskInit(excloud_task_func)

-- 创建拍照功能任务
-- 作用：在单独的任务中运行拍照逻辑
sys.taskInit(capture_func)

-- 创建内存监控任务
-- 作用：在单独的任务中运行内存监控逻辑
sys.taskInit(memory_check)

-- 创建拍照触发任务
-- 作用：每30秒触发一次拍照上传业务
sys.taskInit(AirCAMERA_1040_func)

