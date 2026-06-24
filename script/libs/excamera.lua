--[[
@module excamera
@summary excamera扩展库
@version 1.1
@date    2026.06.23
@author  陈取德
@usage
   用法实例
   注意：excamera.lua适用的产品范围
        Air780系列、Air700系列、Air8000系列：支持SPI摄像头
        Air8101系列：支持USB摄像、DVP摄像头
        合宙所有型号的soc产品都仅支持一路摄像头，所以excamera库不需要管理camera id，只需要调用摄像头的开关和拍照功能即可

    使用excamera库时会有四种应用场景
    1、拍照模式：使用拍照模式时
        按照实际使用的摄像头类型填写配置表 - 创建摄像头excamera.open() - 拍照excamera.photo() - 关闭摄像头 excamera.close()的逻辑使用
    2、扫描模式：当前USB和DVP摄像头不支持扫描模式，仅SPI摄像头可使用
        按照实际使用的摄像头类型填写配置表 - 创建摄像头excamera.open() - 扫描excamera.scan() - 关闭摄像头 excamera.close()的逻辑使用
    3、预览模式（work_mode=2）：SPI摄像头支持实时预览到LCD
        按照实际使用的摄像头类型填写配置表(work_mode=2) - 创建摄像头excamera.open() - excamera.preview() - 关闭摄像头 excamera.close()的逻辑使用
        SPI摄像头：底层camera.preview直接将画面输出到LCD硬件，excamera.preview()仅用于状态管理
        USB摄像头：通过USB帧回调获取帧数据，需要用户自行处理显示
    4、RTMP推流模式：使用USB摄像头进行RTMP推流
        按照实际使用的摄像头类型填写配置表 - 创建摄像头excamera.open() - 推流excamera.rtmp() - 关闭摄像头 excamera.close()的逻辑使用

local excamera = require "excamera"

local spi_camera_param = {
    id = "gc032a",  -- SPI摄像头仅支持"gc032a"、"gc0310"、"bf30a2"，请带引号填写
    i2c_id = 1,             -- 模块上使用的I2C编号
    work_mode = 0,          -- 工作模式，0为拍照模式，1为扫描模式，2为预览模式，3为RTMP推流模式
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
    save_path = "/ram/test.jpg",
    i2c_id = 0  -- 模块上使用的I2C编号
}

local usb_camera_rtmp_param = {
    id = camera.USB, -- 摄像头类型，默认camera.USB
    sensor_width = 1280, -- 摄像头像素宽度，根据摄像头实际参数填写数值
    sensor_height = 720, -- 摄像头像素高度，根据摄像头实际参数填写数值
    usb_port = 1, -- USB端口号
    fps = 15, -- 帧率，每秒15帧
    h264_qp_init = 40, -- H.264编码的初始量化参数
    h264_qp_i_max = 40, -- H.264编码的I帧最大量化参数
    h264_qp_p_max = 25, -- H.264编码的P帧最大量化参数
    h264_imb_bits = 8, -- I帧比特率控制参数
    h264_pmb_bits = 4, -- P帧比特率控制参数
    h264_pframe_nums = 29 -- 每29个P帧插入一个I帧
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
local cam_pwr_wifi, cam_pwdn_wifi, cam_light_wifi = false, false, false
local camera_started
local camera_param_backup      -- 保存完整的摄像头配置参数，供预览使用
local camera_type              -- 摄像头类型："SPI"/"USB"/"DVP"
local preview_active = false   -- 预览模式标志
local preview_cb               -- 预览用户回调函数
local preview_app_id           -- USB摄像头应用ID，预览时使用
local frame_buff0, frame_buff1 -- 预览双缓冲
local preview_usb_fn           -- usb.on 注册的回调句柄，close 时取消注册
local usb_opened = false        -- USB 摄像头是否已初始化，防止重复 camera.init()

-- 设备打开函数：初始化指定类型的摄像头设备
-- 参数：camera_param - 摄像头配置参数表，包含id、i2c_id、work_mode等配置
-- 返回值：成功返回true，失败返回false
-- 支持SPI摄像、USB摄像头、DVP摄像头使用
-- 自动处理异步回调函数，将摄像头业务流程改为同步流程
-- 支持ZBUFF处理照片，支持文件路径处理照片
function excamera.open(camera_param)
    -- 判断摄像头类型是否为字符串类型（用于支持不同型号的摄像头模块）
    if type(camera_param.id) == "string" then
        camera_type = "SPI"

        -- 将excamera的work_mode映射为底层camera.init仅接受的参数范围
        -- work_mode=0(拍照) → only_y=0, scan_mode=0 (AUTO)
        -- work_mode=1(扫描) → only_y=1, scan_mode=1 (SCAN)
        -- work_mode=2(预览) → only_y=0, scan_mode=0 (AUTO，由preview()接管)
        local only_y   = (camera_param.work_mode == 1) and 1 or 0
        local scan_mode = camera_param.work_mode == 2 and 0 or (camera_param.work_mode or 0)

        -- 判断是否需要管理供电使能
        if type(camera_param.camera_pwr) == "number" then
            -- WIFI芯片与4G芯片之间通讯是有延迟的，所以使用WIFI端GPIO时需要增加不少于5毫秒的延时，确保GPIO的配置发送到WIFI芯片并且执行生效；
            -- 摄像头这种复杂应用请使用单芯片的GPIO操作，不要使用双芯片的GPIO操作，否则会有时序问题导致摄像头无法正常工作。
            -- 将供电管脚是否WIFI芯片控制标签设为true，方便后续动作在使用WIFI端GPIO时需要增加延时；
            if camera_param.camera_pwr >= 100 then
                cam_pwr = gpio.setup(camera_param.camera_pwr, 1, gpio.PULLUP)
                cam_pwr_wifi = true
                sys.wait(10)
            else
                cam_pwr = gpio.setup(camera_param.camera_pwr, 1)
            end
        end
        -- 判断是否需要管理摄像头pwdn开关
        if type(camera_param.camera_pwdn) == "number" then
            -- WIFI芯片与4G芯片之间通讯是有延迟的，所以使用WIFI端GPIO时需要增加不少于5毫秒的延时，确保GPIO的配置发送到WIFI芯片并且执行生效；
            -- 摄像头这种复杂应用请使用单芯片的GPIO操作，不要使用双芯片的GPIO操作，否则会有时序问题导致摄像头无法正常工作。
            -- 将摄像头开关管脚是否WIFI芯片控制标签设为true，方便后续动作在使用WIFI端GPIO时需要增加延时；
            if camera_param.camera_pwdn >= 100 then
                cam_pwdn = gpio.setup(camera_param.camera_pwdn, 0)
                cam_pwdn_wifi = true
                sys.wait(10)
            else
                cam_pwdn = gpio.setup(camera_param.camera_pwdn, 0)
            end
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
            -- 注：only_y和scan_mode根据work_mode映射，确保底层接收合法参数
            camera_id = camera.init(1, 24000000, camera_module.mode, camera_module.is_msb, camera_module.rx_bit,
                camera_module.seq_type, camera_module.is_ddr, only_y, scan_mode,
                camera_module.width, camera_module.height)
            if not camera_id then
                log.error("excamera.open", "camera.init失败")
                return false
            end
            -- 通过I2C向摄像头发送配置信息
            -- 注意：camera.init成功后底层已分配硬件资源，一旦i2c.send失败
            -- 必须调用camera.close释放这些资源，否则下次init会"no mem"
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
        if camera_param.id == camera.USB then
            camera_type = "USB"
            if usb_opened then
                log.info("excamera.open", "USB摄像头已初始化，跳过")
                return true
            end
        elseif camera_param.id == camera.DVP then
            camera_type = "DVP"
        else
            camera_type = "UNKNOWN"
            log.info("配置表中“id”参数未配置正确,DVP/USB摄像头请使用camera.USB or camera.DVP这样的常量,不需要加引号,请检查配置表,选择正确类型的配置表填写")
            return false
        end
        -- 如果既不是SPI摄像头，也不是DVP/USB摄像头，则返回错误
        if not camera.init(camera_param) then
            log.info(camera_type .. "摄像头初始化失败，请确认软硬件配置")
            return false
        end
        if camera_type == "USB" then
            usb_opened = true
        end
        camera_id = camera_param.id

        -- 配置摄像头参数（H264编码相关）
        if camera_param.fps then
            camera.config(0, camera.CONF_UVC_FPS, camera_param.fps)
        end
        if camera_param.h264_qp_init then
            camera.config(0, camera.CONF_H264_QP_INIT, camera_param.h264_qp_init)
        end
        if camera_param.h264_qp_i_max then
            camera.config(0, camera.CONF_H264_QP_I_MAX, camera_param.h264_qp_i_max)
        end
        if camera_param.h264_qp_p_max then
            camera.config(0, camera.CONF_H264_QP_P_MAX, camera_param.h264_qp_p_max)
        end
        if camera_param.h264_imb_bits then
            camera.config(0, camera.CONF_H264_IMB_BITS, camera_param.h264_imb_bits)
        end
        if camera_param.h264_pmb_bits then
            camera.config(0, camera.CONF_H264_PMB_BITS, camera_param.h264_pmb_bits)
        end
        if camera_param.h264_pframe_nums then
            camera.config(0, camera.CONF_H264_PFRAME_NUMS, camera_param.h264_pframe_nums)
        end
    end

    -- 保存摄像头配置参数，供 preview() 使用
    camera_param_backup = camera_param

    -- 注册摄像头事件回调处理（仅 SPI 摄像头需要 scanned 回调）
    -- 注意：USB/DVP 摄像头的回调在 excamera.preview() 中通过 camera.on(id, "usb_raw", ...) 注册
    --       C 层代码中 scanned 和 usb_raw 是 if/else if 互斥关系
    --       如果同时注册 scanned，USB 事件的 usb_raw 分支永远无法执行
    if camera_type == "SPI" or camera_type == "DVP" then
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
    end
    -- 停止摄像头当前采集，释放内存空间
    camera.stop(camera_id)

    -- 处理图像保存路径，支持内存缓冲区(ZBUFF)或文件路径
    if camera_param.save_path == "ZBUFF" then
        if camera_buff == nil then
            -- 根据摄像头型号设置图像分辨率
            if camera_param.id == "bf30a2" then
                h, w = 240, 320 -- BF30A2摄像头分辨率
            elseif camera_param.id == "gc032a" or camera_param.id == "gc0310" then
                h, w = 640, 480 -- GC032A/GC0310摄像头分辨率
            elseif camera_param.id == camera.USB or camera_param.id == camera.DVP then
                -- USB或DVP摄像头使用传入的分辨率参数
                h, w = camera_param.sensor_height, camera_param.sensor_width
            end
            -- 创建ZBUFF内存缓冲区，用于存储图像数据
            -- 参数1: 缓冲区大小（宽*高*2，2字节/像素）
            -- 参数2: 对齐方式
            camera_buff = zbuff.create(h * w * 1.5, 0)
            if camera_buff == nil then
                -- 缓冲区创建失败
                log.info("内存不足，ZBUFF创建失败，请重启系统")
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
        -- WIFI芯片与4G芯片之间通讯是有延迟的，所以使用WIFI端GPIO时需要增加不少于5毫秒的延时，确保GPIO的配置发送到WIFI芯片并且执行生效；
        -- 摄像头这种复杂应用请使用单芯片的GPIO操作，不要使用双芯片的GPIO操作，否则会有时序问题导致摄像头无法正常工作。
        -- 将补光灯管脚是否WIFI芯片控制标签设为true，方便后续动作在使用WIFI端GPIO时需要增加延时；
        if camera_param.camera_light >= 100 then
            cam_light = gpio.setup(camera_param.camera_light, 0)
            cam_light_wifi = true
            sys.wait(10)
        else
            cam_light = gpio.setup(camera_param.camera_light, 0)
        end
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
    -- 如果补光灯是WIFI芯片控制，需要增加延时确保GPIO配置生效
    if cam_light_wifi then
        sys.wait(10)
    end
    log.info("照片存储路径", path)
    -- 执行拍照操作，保存到指定路径
    if camera.capture(camera_id, path, 1, x, y, w, h) then
        -- 等待拍照完成事件，超时时间5000ms
        result = sys.waitUntil("CAPTURE_DONE", 5000)
        -- 保护执行关闭补光灯，如果上面没有配置补光灯，该函数也不会报错
        pcall(cam_light, 0)
        -- 如果补光灯是WIFI芯片控制，需要增加延时确保GPIO配置生效
        if cam_light_wifi then
            sys.wait(10)
        end
        -- 停止摄像头采集，释放内存空间
        camera.stop(camera_id)
        if result then
            -- 拍照成功
            log.info("拍照完成")
        else
            -- 拍照超时
            log.info("拍照超时")
            return false
        end
    else
        -- 保护执行关闭补光灯，如果上面没有配置补光灯，该函数也不会报错
        pcall(cam_light, 0)
        -- 如果补光灯是WIFI芯片控制，需要增加延时确保GPIO配置生效
        if cam_light_wifi then
            sys.wait(10)
        end
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
    -- 如果补光灯是WIFI芯片控制，需要增加延时确保GPIO配置生效
    if cam_light_wifi then
        sys.wait(10)
    end
    -- 等待SCAN_DONE事件，超时时间根据用户配置
    result, data = sys.waitUntil("SCAN_DONE", ms)
    -- 停止摄像头采集，释放内存空间
    camera.stop(camera_id)
    -- 保护执行关闭补光灯，如果上面没有配置补光灯，该函数也不会报错
    pcall(cam_light, 0)
    -- 如果补光灯是WIFI芯片控制，需要增加延时确保GPIO配置生效
    if cam_light_wifi then
        sys.wait(10)
    end
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

--[[
RTMP推流功能
@return 成功返回true，失败返回false
--]]
function excamera.rtmp()
    if not camera_id then
        log.error("excamera.rtmp", "摄像头未初始化")
        return false
    end

    if camera.start(camera_id) then
        log.info("excamera.rtmp", "摄像头启动成功")
        camera_started = true
        return true
    else
        log.error("excamera.rtmp", "无法启动摄像头")
        return false
    end
end

-- 预览函数：开启摄像头实时预览
-- 参数：cb - 可选回调函数，接收事件通知，原型 cb(event, ...)
--       event取值：
--         "connected"    - USB摄像头已连接，后续参数 (app_id)
--         "disconnected" - USB摄像头已断开，后续参数 (app_id)
--         "frame"        - 新帧数据到达，后续参数 (buff, len)
--         "error"        - 发生错误，后续参数 (msg)
-- 返回值：成功返回true，失败返回false
-- 注意：必须在excamera.open()且work_mode=2之后调用
-- 支持SPI摄像头（GC032A/GC0310/BF30A2）和USB摄像头：
--   SPI摄像头：画面由底层camera.preview直接送往LCD，无需用户干预，无回调
--   USB摄像头：通过回调函数接收帧数据，需要自行处理显示逻辑
function excamera.preview(cb)
    if not camera_param_backup then
        log.error("excamera.preview", "请先调用 excamera.open()")
        return false
    end
    -- 仅 SPI 摄像头需要 work_mode=2 标识预览意图
    if camera_type == "SPI" and camera_param_backup.work_mode ~= 2 then
        log.error("excamera.preview", "SPI预览模式请在excamera.open()中设置 work_mode=2")
        return false
    end

    if preview_active then
        log.warn("excamera.preview", "预览已启动，请勿重复调用")
        return true
    end

    -- SPI/DVP摄像头：启动数据采集，硬件直接输出到LCD
    if camera_type == "SPI" or camera_type == "DVP" then
        if not camera.start(camera_id) then
            log.error("excamera.preview", camera_type .. "摄像头启动失败")
            return false
        end
        if not camera.preview(camera_id, true) then
            log.error("excamera.preview", camera_type .. "摄像头预览启动失败")
            camera.stop(camera_id)
            return false
        end
        preview_active = true
        preview_cb = cb
        log.info("excamera.preview", camera_type .. "摄像头预览已启动")
        return true
    end

    -- USB摄像头：注册事件回调，开启解码管线
    if camera_type == "USB" then
        preview_cb = cb
        preview_active = true

        -- 确保USB掉电→设为主机模式→上电，触发USB重新枚举产生EV_CONNECT事件
        -- 注意：camera.on(USB, "usb_raw") 必须在掉电之后注册，
        --       否则 USB 栈重置会丢失已注册的回调
        -- 某些平台（如Air8101）固件可能未编译usb核心库，需要保护访问
        -- if pm.power then
        --     pm.power(pm.USB, false)
        -- end
        sys.wait(500)
        if usb and usb.mode then
            usb.mode(0, usb.HOST)
        end
        if pm.power then
            pm.power(pm.USB, true)
        end

        -- 等待USB栈稳定后再注册回调（枚举约需1~2秒完成）
        sys.wait(100)

        -- 注册摄像头事件回调（连接/断开/新帧/异常）
        -- 必须在掉电重枚举之后注册，否则USB栈重置会丢失回调
        camera.on(camera.USB, "usb_raw", function(app_id, event, param)
            if not preview_active then
                return
            end

            -- 收到新帧数据
            if event == usb.EV_NEW_RX then
                if preview_cb then
                    if param == 0 and frame_buff0 then
                        preview_cb("frame", frame_buff0, frame_buff0:used())
                    elseif param == 1 and frame_buff1 then
                        preview_cb("frame", frame_buff1, frame_buff1:used())
                    end
                end
                return
            end

            -- USB摄像头连接事件：枚举分辨率，启动推流
            if event == usb.EV_CONNECT then
                preview_app_id = app_id
                log.info("excamera.preview", "usb摄像头已连接，app_id", app_id)

                if preview_cb then
                    preview_cb("connected", app_id)
                end

                -- 获取配置表中的分辨率参数
                local target_w = camera_param_backup.sensor_width or 640
                local target_h = camera_param_backup.sensor_height or 480

                -- 创建双缓冲MJPEG帧缓冲
                local buff_size = math.ceil(target_w * target_h)
                frame_buff0 = zbuff.create(buff_size)
                frame_buff1 = zbuff.create(buff_size)
                if not frame_buff0 or not frame_buff1 then
                    log.error("excamera.preview", "zbuff创建失败，内存不足")
                    if preview_cb then
                        preview_cb("error", "内存不足，zbuff创建失败")
                    end
                    return
                end

                -- 枚举UVC格式，匹配MJPEG+目标分辨率
                local res, format_num = camera.get_usb_config(app_id, camera.CONF_UVC_FORMAT)
                log.info("excamera.preview", "UVC格式数量", format_num)

                local found = false
                for fmt = 1, format_num do
                    res, ftype, frame_num = camera.get_usb_config(app_id, camera.CONF_UVC_FORMAT, fmt)
                    for frm = 1, frame_num do
                        res, fps, w, h = camera.get_usb_config(app_id, camera.CONF_UVC_RESOLUTION, fmt, frm)
                        if w == target_w and h == target_h and ftype == camera.FORMAT_MJPG then
                            log.info("excamera.preview", "匹配分辨率", w, "x", h, "MJPEG")
                            camera.set_usb_config(app_id, camera.CONF_UVC_RESOLUTION, fmt, frm)
                            found = true
                            break
                        end
                    end
                    if found then break end
                end

                if not found then
                    log.warn("excamera.preview", "未匹配到", target_w, "x", target_h, "MJPEG，使用默认分辨率")
                end

                -- 启动双缓冲循环推流
                camera.cache(camera.USB, app_id, frame_buff0, frame_buff1)
                camera.stream(camera.USB, app_id, 0)
                log.info("excamera.preview", "推流已启动", target_w, "x", target_h)
                return
            end

            -- USB摄像头断开事件
            if event == usb.EV_DISCONNECT then
                log.info("excamera.preview", "usb摄像头已断开，app_id", app_id)
                preview_app_id = nil
                if preview_cb then
                    preview_cb("disconnected", app_id)
                end
                return
            end

            -- 接收数据异常
            if event == usb.EV_RX_ERR then
                log.warn("excamera.preview", "usb摄像头接收数据异常")
                if preview_cb then
                    preview_cb("error", "usb摄像头接收数据异常")
                end
                return
            end
        end)

        -- 开启camera预览功能（底层JPEG解码任务）
        camera.preview(camera.USB, true)

        log.info("excamera.preview", "USB摄像头预览初始化完成，等待摄像头连接...")
        return true
    end

    log.error("excamera.preview", "不支持的摄像头类型:", camera_type, "camera_id:", camera_id)
    return false
end

-- 关闭函数：释放摄像头资源
-- 参数：remain_zbuff - 可选，是否保留ZBUFF缓冲区，默认释放
function excamera.close(remain_zbuff)
    -- 如果处于预览模式，先停止预览
    if preview_active then
        log.info("excamera.close", "停止预览模式")
        preview_active = false
        preview_cb = nil
        camera_param_backup = nil

        -- SPI/DVP摄像头：关闭硬件预览，停止数据采集
        if camera_type == "SPI" or camera_type == "DVP" then
            camera.preview(camera_id, false)
            camera.stop(camera_id)
            camera.close(camera_id)
            -- 跳转到GPIO/I2C清理
            goto PREVIEW_CLEANUP
        end

        -- USB摄像头：停止推流和JPEG解码，取消usb.on回调
        if camera_type == "USB" then
            if preview_app_id then
                camera.preview(camera.USB, false)
                camera.close(preview_app_id)
                preview_app_id = nil
            end
            -- 解除usb.on回调注册（传入nil覆盖）
            if preview_usb_fn then
                -- usb.on(0, nil)
                preview_usb_fn = nil
            end
        end

        -- 释放双缓冲
        if frame_buff0 then
            frame_buff0:free()
            frame_buff0 = nil
        end
        if frame_buff1 then
            frame_buff1:free()
            frame_buff1 = nil
        end

        -- USB预览清理完毕后跳过后续 camera.close(camera_id) 逻辑
        usb_opened = false
        return
    end

    if camera_id then
        -- 如果启动摄像头之后，还没有stop，则此处stop
        -- 目前在rtmp场景下需要
        if camera_started then
            camera_started = false
            camera.stop(camera_id)
        end

        -- 关闭摄像头，释放摄像头硬件资源
        camera.close(camera_id)
    end

    ::PREVIEW_CLEANUP::
    -- 仅SPI摄像头需要关闭I2C接口，USB和DVP摄像头不需要
    if camera_type == "SPI" then
        i2c.close(camera_i2c)
    end
    -- 保护执行摄像头使能关闭，如果上面没有配置摄像头使能管脚，该函数也不会报错
    pcall(cam_pwr, 0)
    -- 如果供电管脚是WIFI芯片控制，需要增加延时确保GPIO配置生效
    if cam_pwr_wifi then
        sys.wait(10)
    end
    -- 保护执行摄像头开关关闭，如果上面没有配置摄像头开关管脚，该函数也不会报错
    pcall(cam_pwdn, 1)
    -- 如果摄像头开关管脚是WIFI芯片控制，需要增加延时确保GPIO配置生效
    if cam_pwdn_wifi then
        sys.wait(10)
    end

    -- 如果使用了内存缓冲区，释放相关资源
    if type(path) == "userdata" and not remain_zbuff then
        -- 置空缓冲区引用，便于垃圾回收
        camera_buff:free()
        camera_buff = nil
        path = nil
        -- 记录当前系统剩余内存情况
        log.info("剩余内存", rtos.meminfo("sys"))
    end
    cam_pwr_wifi, cam_pwdn_wifi, cam_light_wifi, camera_id, camera_type = nil, nil, nil, nil, nil
    usb_opened = false
    camera_param_backup = nil
end

return excamera
