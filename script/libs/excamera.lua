--[[
@module excamera
@summary excamera扩展库
@version 1.0
@date    2025.10.21
@author  陈取德
@usage
   用法实例
   注意：excamera.lua适用的产品范围
        Air780系列、Air700系列、Air8000系列：支持SPI摄像头
        Air8101系列：支持USB摄像、DVP摄像头
        合宙所有型号的soc产品都仅支持一路摄像头，所以excamera库不需要管理camera id，只需要调用摄像头的开关和拍照功能即可

    使用excamera库时会有两种应用场景
    1、拍照模式：使用拍照模式时
        按照实际使用的摄像头类型填写配置表 - 创建摄像头excamera.open() - 拍照excamera.photo() - 关闭摄像头 excamera.close()的逻辑使用
    2、扫描模式：当前USB和DVP摄像头不支持扫描模式，仅SPI摄像头可使用
        按照实际使用的摄像头类型填写配置表 - 创建摄像头excamera.open() - 扫描excamera.scan() - 关闭摄像头 excamera.close()的逻辑使用

local excamera = require "excamera"

local spi_camera_param = {
    id = "gc032a",  -- SPI摄像头仅支持"gc032a"、"gc0310"、"bf30a2"，请带引号填写
    i2c_id = 1,             -- 模块上使用的I2C编号
    work_mode = 0,          -- 工作模式，0为拍照模式，1为扫描模式
    save_path = "ZBUFF",    -- 拍照结果存储路径，可用"ZBUFF"交由excamera库内部管理
    camera_pwr = 2 ,        -- 摄像头使能管脚，填写GPIO号即可，无则填nil
    camera_pwdn = 5 ,       -- 摄像头pwdn开关脚，填写GPIO号即可，无则填nil
    camera_light = 25       -- 摄像头补光灯控制管脚，填写GPIO号即可，无则填nil
}

local usb_camera_param = {
    id = camera.USB , -- 摄像头类型，默认camera.USB
    sensor_width = 1280, -- 摄像头像素宽度，根据摄像头实际参数填写数值
    sensor_height = 720, -- 摄像头像素高度，根据摄像头实际参数填写数值
    usb_port = 1 ,
    save_path = "/ram/test.jpg"
}

local dvp_camera_param = {
    id = camera.DVP, -- 摄像头类型，默认camera.DVP
    sensor_width = 1280, -- 摄像头像素宽度，根据摄像头实际参数填写数值
    sensor_height = 720, -- 摄像头像素高度，根据摄像头实际参数填写数值
    save_path = "/ram/test.jpg"
}

sys.taskInit(function()
    local camera_id
    while true do
        sys.waitUntil("ONCE_CAPTURE")
        camera_id = excamera.open(spi_camera_param)
        log.info("初始化状态", camera_id)
        local result ,data = excamera.photo()
        log.info("拍完了",data)
        excamera.close()
    end
end)
sys.run()
]] --
local excamera = {}
local h, w
local camera_id, path, camera_buff, camera_i2c, data, result
local cam_pwr, cam_pwdn, cam_light

-- 设备打开函数：初始化指定类型的摄像头设备
-- 参数：camera_param - 摄像头配置参数表，包含id、i2c_id、work_mode等配置
-- 返回值：成功返回camera_id，失败返回false
-- 支持SPI摄像、USB摄像头、DVP摄像头使用
-- 自动处理异步回调函数，将摄像头业务流程改为同步流程
-- 支持ZBUFF处理照片，支持文件路径处理照片
function excamera.open(camera_param)
    -- 判断摄像头类型是否为字符串类型（用于支持不同型号的摄像头模块）
    if type(camera_param.id) == "string" then
        -- 判断是否需要管理供电使能
        if type(camera_param.camera_pwr) == "number" then
            cam_pwr = gpio.setup(camera_param.camera_pwr, 1)
        end
        -- 判断是否需要管理摄像头pwdn开关
        if type(camera_param.camera_pwdn) == "number" then
            cam_pwdn = gpio.setup(camera_param.camera_pwdn, 0)
            -- 为8000暂时兼容，后续版本会移除
            sys.wait(10)
        end
        -- 配置I2C接口，用于与摄像头通信
        if i2c.setup(camera_param.i2c_id, i2c.FAST) then
            -- 保存I2C接口ID到camera_i2c，用于局内调用
            camera_i2c = camera_param.i2c_id
            -- 保护执行配置文件加载，并赋值给camera_module，便于后续调用配置表信息
            local result, camera_module = pcall(require, camera_param.id)
            if not result then
                log.error("excamera.open", camera_param.id .. ".lua文件加载失败")
                return false
            end
            -- 通过摄像头配置表信息初始化摄像头
            camera_id = camera.init(1, 24000000, camera_module.mode, camera_module.is_msb, camera_module.rx_bit,
                camera_module.seq_type, camera_module.is_ddr, camera_param.work_mode, camera_param.work_mode,
                camera_module.width, camera_module.height)
            if not camera_id then
                log.error("excamera.open", "camera.init失败")
                return false
            end
            -- 通过I2C向摄像头发送配置信息
            for i = 1, #camera_module.init_cmds do
                result = i2c.send(camera_param.i2c_id, camera_module.i2c_slave_addr, camera_module.init_cmds[i], 1)
                if not result then
                    log.error("excamera.open", "i2c.send失败")
                    return false
                end
            end
        else
            -- I2C配置失败，记录错误日志
            log.info("I2C配置错误,请确认I2C接口配置是否正确")
            return false
        end
    else
        -- 如果不是SPI摄像头，则按照DVP/USB摄像头的初始化方式处理
        -- 如果既不是SPI摄像头，也不是DVP/USB摄像头，则返回错误
        if not camera.init(camera_param) then
            log.info(
                "配置表中“id”参数未配置正确,DVP/USB摄像头请使用camera.USB or camera.DVP这样的常量,不需要加引号,请检查配置表,选择正确类型的配置表填写")
            return false
        end
        camera_id = camera_param.id

    end

    -- 注册摄像头事件回调处理
    camera.on(camera_id, "scanned", function(id, str)
        -- 如果返回字符串，表示扫码成功并获得结果
        if type(str) == 'string' then
            log.info("扫码结果", str)
            sys.publish("SCAN_DONE", str)
            -- 如果返回false，表示摄像头没有有效数据
        elseif str == false then
            log.error("摄像头没有数据")
            -- 如果返回true或数字，表示成功捕获到图像文件大小
        elseif str == true or type(str) == 'number' then
            log.info("摄像头数据", str)
            -- 发布CAPTURE_DONE事件，通知其他任务拍照已完成
            sys.publish("CAPTURE_DONE", true)
        end
    end)
    -- 停止摄像头当前采集，释放内存空间
    camera.stop(camera_id)

    -- 处理图像保存路径，支持内存缓冲区(ZBUFF)或文件路径
    if camera_param.save_path == "ZBUFF" then
        if camera_buff == nil then
            -- 根据摄像头型号设置图像分辨率
            if camera_param.id == "bf30a2" then
                h, w = 240, 320 -- BF30A2摄像头分辨率
            elseif camera_param.id == "gc032a" or "gc0310" then
                h, w = 640, 480 -- GC032A/GC0310摄像头分辨率
            elseif camera_param.id == camera.USB or camera.DVP then
                -- USB或DVP摄像头使用传入的分辨率参数
                h, w = camera_param.sensor_height, camera_param.sensor_width
            end


            -- 创建ZBUFF内存缓冲区，用于存储图像数据
            -- 参数1: 缓冲区大小（宽*高*2，2字节/像素）
            -- 参数2: 对齐方式
            camera_buff = zbuff.create(h * w * 2, 0)
            if camera_buff == nil then
                -- 缓冲区创建失败
                log.info("ZBUFF创建失败")
                return false
            else
                -- 缓冲区创建成功，保存到path变量
                path = camera_buff
            end
        end
    else
        -- 如果是文件路径则赋值到path，便于后面调用
        path = camera_param.save_path
    end
    -- 判断是否需要管理摄像头补光灯
    if type(camera_param.camera_light) == "number" then
        cam_light = gpio.setup(camera_param.camera_light, 0)
    end
    -- 返回初始化动作结果
    return true
end

-- 拍照函数：使用指定摄像头拍摄照片并保存
-- 参数：x, y, w, h - 可选，指定拍摄区域的起始坐标和尺寸（裁剪区域）
-- 返回值：成功返回(true, 保存路径)，失败返回false
-- 使用ZBUFF处理照片时，每次调用该接口为了避免内存爆满，会覆盖写入ZBUFF区，保证ZBUFF区始终只有一张照片，处理上传或者存储后再调用该接口，避免照片丢失
function excamera.photo(x, y, w, h)
    if not camera_id then
        log.info("摄像头初始化失败，请重新确认软硬件配置")
        return false
    end
    -- 开始摄像头图像采集
    camera.start(camera_id)
    -- 如果使用内存缓冲区保存，重置缓冲区位置指针到开始位置
    if type(path) == "userdata" then
        camera_buff:seek(0)
    end
    -- 保护执行打开补光灯，如果上面没有配置补光灯，该函数也不会报错
    pcall(cam_light, 1)
    log.info("照片存储路径", path)
    -- 执行拍照操作，保存到指定路径
    if camera.capture(camera_id, path, 1, x, y, w, h) then
        -- 等待拍照完成事件，超时时间5000ms
        result = sys.waitUntil("CAPTURE_DONE", 5000)
        -- 保护执行关闭补光灯，如果上面没有配置补光灯，该函数也不会报错
        pcall(cam_light, 0)
        -- 停止摄像头采集，释放内存空间
        camera.stop(camera_id)
        if result then
            -- 拍照成功
            log.info("拍照完成")
        else
            -- 拍照超时
            log.info("拍照成功，无照片生成")
            return false
        end
    else
        -- 保护执行关闭补光灯，如果上面没有配置补光灯，该函数也不会报错
        pcall(cam_light, 0)
        -- 停止摄像头采集，释放内存空间
        camera.stop(camera_id)
        -- 拍照操作失败
        log.info("拍照失败，请重试")
        return false
    end

    -- 返回成功状态和照片保存路径
    return true, path
end

-- 扫描函数：使用摄像头进行扫描（如二维码/条形码扫描）
-- 参数：扫描时长ms，单位毫秒
-- 返回值：成功返回(true, 扫描数据)，超时未有扫描结果返回false
function excamera.scan(ms)
    if not camera_id then
        log.info("摄像头初始化失败，请重新确认软硬件配置")
        return false
    end
    -- 开始摄像头图像采集
    camera.start(camera_id)
    -- 保护执行打开补光灯，如果上面没有配置补光灯，该函数也不会报错
    pcall(cam_light, 1)
    -- 等待SCAN_DONE事件，超时时间根据用户配置
    result, data = sys.waitUntil("SCAN_DONE", ms)
    -- 停止摄像头采集，释放内存空间
    camera.stop(camera_id)
    -- 保护执行关闭补光灯，如果上面没有配置补光灯，该函数也不会报错
    pcall(cam_light, 0)
    if result then
        log.info("扫描完成，扫描结果为：", data)
    else
        log.info(ms .. "秒内未扫描成功，请将摄像头对准二维码")
        return false
    end
    -- 返回成功状态和扫描到的数据
    return true, data
end

-- 录像函数：使用指定摄像头录制视频
-- 参数：
--   file_path - 视频保存路径，如"/sd/video.mp4"，文件后缀必须为mp4
--   duration - 录制时长，单位毫秒
-- 返回值：成功返回(true, 保存路径)，失败返回false
-- 注意：在使用此函数前，需要先使用excamera.open配置摄像头
function excamera.video(file_path, duration)

    if not file_path or not duration then
        log.error("excamera.video", "参数配置错误")
        return false
    end
    
    if not camera_id then
        log.error("excamera.video", "摄像头未初始化")
        return false
    end

    log.info("excamera.video", "开始录制视频到", file_path)

    -- 打印内存信息
    log.info("excamera.video", "lua内存:", rtos.meminfo())
    log.info("excamera.video", "sys内存:", rtos.meminfo("sys"))
    
    -- 1. 启动摄像头
    if camera.start(camera_id) then
        -- 2. 开始MP4录制
        if camera.capture(camera_id, file_path) then
            -- 3. 等待录制时长
            sys.wait(duration)
            
            -- 4. 停止录制
            camera.stop(camera_id)
            
            -- 再次打印内存信息
            log.info("excamera.video", "lua内存:", rtos.meminfo())
            log.info("excamera.video", "sys内存:", rtos.meminfo("sys"))
            
            log.info("excamera.video", "视频录制完成", file_path)
            return true, file_path
        else
            -- 录制启动失败，关闭摄像头
            camera.stop(camera_id)
            log.error("excamera.video", "无法开始录制")
            return false
        end
    else
        log.error("excamera.video", "无法启动摄像头")
        return false
    end
end

-- 关闭函数：释放摄像头资源
-- 参数：camera_id - 摄像头ID
function excamera.close(remain_zbuff)
    if camera_id then
        -- 关闭摄像头，释放摄像头硬件资源
        camera.close(camera_id)
    end
    -- 关闭SPI摄像头时需要关闭I2C接口，释放通信总线资源
    -- USB和DVP摄像头不需要关闭i2c,所以需要判断摄像头ID返回值，USB为32，DVP为0，SPI为1
    if camera_id == 1 then
        i2c.close(camera_i2c)
    end
    -- 保护执行摄像头使能关闭，如果上面没有配置摄像头使能管脚，该函数也不会报错
    pcall(cam_pwr, 0)
    -- 保护执行摄像头开关关闭，如果上面没有配置摄像头开关管脚，该函数也不会报错
    pcall(cam_pwdn, 1)
    -- 如果使用了内存缓冲区，释放相关资源
    if type(path) == "userdata" and not remain_zbuff then
        -- 置空缓冲区引用，便于垃圾回收
        camera_buff:free()
        camera_buff = nil
        path = nil
        -- 记录当前系统剩余内存情况
        log.info("剩余内存", rtos.meminfo("sys"))
    end
    camera_id = nil
end

return excamera
