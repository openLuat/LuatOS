--[[
@module  photo_to_aircloud
@summary AirCAMERA_1040 gc032a摄像头拍照上传应用模块
@version 1.0
@date    2026.4.30
@author  陈取德
@usage
本demo主要使用AirCAMERA_1040 gc032a摄像头完成拍照上传任务
Air780EPM的sys ram内存资源只有2.3M，在使用camera功能时，需要非常谨慎，避免内存泄漏导致系统崩溃，需要注意以下情况：
    1、exmcamera业务执行时，必须要确保有连续的内存空间，否则会导致excamera.open()初始化失败，需要的空间计算方式为：
        （ 摄像头像素高 X 摄像头像素宽 X 2 ），用“GC032A”举例，内存空间为：640 * 480 * 2 = 614400 (B) ≈ 620KB
    2、当使用ZBUFF方式存储照片，或者将照片放到 /ram/ 路径下保存时，必须确保有更多的内存连续空间，需要的总空间大小计算方式为：
        （ 摄像头像素高 X 摄像头像素宽 X 3.5 ），用“GC032A”举例，内存空间为：640 * 480 * 3.5 = 1075200 (B) ≈ 1MB
    3、本DEMO为常规模式下，摄像头稳定供电使用，DEMO逻辑为excamera.open()初始化完摄像头后，只需要重复调用excamera.photo()拍照即可，不需要反复的初始化关闭摄像头；
    4、在实际应用中，务必将摄像头初始化的优先级排前，因为摄像头业务占用内存过大，尽早的初始化可以确保摄像头初始化时拿到足够的连续内存，确保后续拍照时能够正常执行；
    5、Air780EPM的内存非常有限，在摄像头需求高的产品设计中，请选择Air780EHM/EGH/EHV、Air8000、Air700ECH这类 8MB + 8MB 的SOC，更大的内存才是摄像头业务稳定运行的最优解；
    6、低功耗模式下使用excamera请参考lowpower DEMO，链接：https://docs.openluat.com/air780epm/luatos/app/lowpower/sleep/#_1 
]] --
-- 摄像头拍照模块
-- 功能：提供摄像头初始化、拍照和资源管理功能
-- 引入excamera扩展库模块
local excamera = require "excamera"
-- 引入httpplus扩展库模块
local httpplus = require "httpplus"
-- 引入exmux扩展库模块
local exmux = require "exmux"
-- 导入excloud库
local excloud = require "excloud"
-- pm.ioVol(pm.IOVOL_ALL_GPIO, 2800) 

-- 配置excloud参数
local project_auth_key = "123456"

-- 硬件I2C/SPI配置，当您使用合宙开发板时，请根据具体的开发板版本选择对应的变量，
-- exmux库将会自动处理开发板上的I2C/SPI外设，确保总线通讯正常
-- 当您使用自己的制作的板子，请参考exmux库的文档，配置对应的变量：https://docs.openluat.com/osapi/ext/exmux/
-- local HARDWARE_ENV = "DEV_BOARD_8000_V2.0"
-- local HARDWARE_ENV = "DEV_BOARD_780_V1.2"
local HARDWARE_ENV = "DEV_BOARD_780_V1.3"

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
        device_type = 1, -- 4G设备
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
    -- 初始化开发板
    exmux.setup(HARDWARE_ENV)
    -- 出现异常后重新初始化，最多重试5次
    while retry_count < 5 do
        -- 配置gc032a摄像头参数表
        local spi_camera_param = {
            id = "gc032a", -- SPI摄像头仅支持"gc032a"、"gc0310"、"bf30a2"，请带引号填写
            i2c_id = 1, -- 模块上使用的I2C编号
            work_mode = 0, -- 工作模式，0为拍照模式，1为扫描模式
            save_path = save_method, -- 拍照结果存储路径，可用"ZBUFF"交由excamera库内部管理
            camera_pwr = 2, -- 摄像头使能管脚，填写GPIO号即可，无则填nil
            camera_pwdn = 5, -- 摄像头pwdn开关脚，填写GPIO号即可，无则填nil
            camera_light = nil -- 摄像头补光灯控制管脚，填写GPIO号即可，无则填nil
        }
        -- 打开外设分组
        exmux.open("i2c1")
        -- 初始化摄像头，传入配置参数
        result = excamera.open(spi_camera_param)
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
                os.remove(spi_camera_param.save_path)
            end
        end
        -- 关闭摄像头，释放资源
        -- 使用ZBUFF存储方式时，close传入true后，excamera内部创建的ZBUFF会缩减至0字节，放出内存但是不释放ZBUFF，便于下次拍照时调用；
        -- 重复申请和释放ZBUFF会导致垃圾内存堆积，影响系统内存；
        excamera.close(true)
        -- 关闭外设分组
        exmux.close("i2c1")
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

-- 按键触发函数，用于手动拍照拍照
local function press_key()
    log.info("boot press")
    sys.publish("ONCE_CAPTURE")
end
-- 配置BOOT按键引脚为输入模式，下拉电阻，上升沿触发
gpio.setup(0, press_key, gpio.PULLDOWN, gpio.RISING)
gpio.debounce(0, 100, 1)

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

