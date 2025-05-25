
local AirCAMERA_1020 =
{
    id = camera.DVP,
    -- capture_photo_buff：拍照使用的zbuff缓冲区
    -- opend：是否已经成功打开
}

-- 摄像头事件回调函数
local function camera_scan_cbfunc(id, str)
    log.info("camera_scan_cbfunc", id, str)
    --str为string类型时，表示扫码模式下扫码结果的回调
    --str为扫码识别后的解码字符串
    if type(str) == 'string' then
        log.info("scan code result", str)
    --str为false时，表示摄像头没有正常工作
    elseif str == false then
        log.error("no data")
    --str为number类型时，表示拍摄到的照片字节大小
    else
        log.info("capture photo data", str)
        sys.publish("AirCAMERA_1020_CAPTURE_IND", true)
    end
end


--打开AirCAMERA_1020摄像头；

--width：number类型；
--       表示摄像头拍照时的宽度，单位为像素；
--       取值范围：大于0，并且和height的乘积不能超过1280*720；
--       如果没有传入此参数，则默认为1280；
--height：number类型；
--       表示摄像头拍照时的宽度，单位为像素；
--       取值范围：大于0，并且和width的乘积不能超过1280*720；
--       如果没有传入此参数，则默认为720；

--返回值：成功返回true，失败返回false
function AirCAMERA_1020.open(width, height)
    --如果没有传入参数，width和height都使用默认值
    width = width or 1280
    height = height or 720

    --判断width和height参数的合法性
    if width<0 or height<0 or width*height>1280*720 then
        log.error("AirCAMERA_1020.open error", "invalid width or height", width, height)
        return false
    end

    --如果没有分配过存储照片的内存数据，此处申请200KB的zbuff内存空间
    --如果拍照过程中，发现200KB的空间不够使用，会自动扩充空间
    if AirCAMERA_1020.capture_photo_buff==nil then
        AirCAMERA_1020.capture_photo_buff = zbuff.create(200 * 1024, 0, zbuff.HEAP_PSRAM)
        if AirCAMERA_1020.capture_photo_buff == nil then
            log.error("AirCAMERA_1020.open error", "malloc mem fail")
            return false
        end
    end

    --初始化摄像头
    if not camera.init({id = AirCAMERA_1020.id, sensor_width = width, sensor_height = height}) then
        log.error("AirCAMERA_1020.open error", "camera.init fail")
        AirCAMERA_1020.capture_photo_buff:free()
        AirCAMERA_1020.capture_photo_buff = nil
        return false
    end

    --注册摄像头事件回调函数camera_scan_cbfunc
    --摄像头的异步事件都会通过回调函数通知结果
    camera.on(AirCAMERA_1020.id, "scanned", camera_scan_cbfunc)

    --设置摄像头已经成功打开的标志
    AirCAMERA_1020.opend = true

    return true
end


--使用AirCAMERA_1020摄像头拍照；必须在task中使用

--返回值：成功返回照片的zbuff内存数据，失败返回false
function AirCAMERA_1020.capture()

    --检查是否运行在task中
    local co, is_main = coroutine.running()
    -- Lua 5.1: 直接返回协程（主协程返回 nil）
    -- Lua 5.2+: 返回协程和是否是主协程
    if type(co) == "thread" and is_main then
        log.error("AirCAMERA_1020.capture error", "must in task", type(co) == "thread", is_main)
        return false
    end
    if co == nil then
        log.error("AirCAMERA_1020.capture error", "must in task", co)
        return false
    end

    --如果摄像头没有打开
    if not AirCAMERA_1020.opend then
        log.error("AirCAMERA_1020.capture error", "camera isn't opend")
        return false
    end


    if not camera.start(AirCAMERA_1020.id) then
        log.error("AirCAMERA_1020.capture error", "camera.start fail")
        return false
    end

    --启动拍照动作，拍照质量90%，如果拍照成功，照片数据存储到AirCAMERA_1020.capture_photo_buff的zbuff内存中
    if not camera.capture(AirCAMERA_1020.id, AirCAMERA_1020.capture_photo_buff, 1) then
        log.error("AirCAMERA_1020.capture error", "camera.capture sync fail")
        return false
    end
    
    --阻塞等待拍照结果，如果5秒钟没有等到结果，超时失败退出阻塞等待状态
    result = sys.waitUntil("AirCAMERA_1020_CAPTURE_IND", 5000)
    --打印拍摄的照片字节大小
    log.info("AirCAMERA_1020.capture", "photo size", AirCAMERA_1020.capture_photo_buff:used())
    if not result then
        log.error("AirCAMERA_1020.capture error", "camera.capture async fail")
        return false
    end

    --停止拍照
    camera.stop(AirCAMERA_1020.id)

    --返回存储照片数据的zbuff内存
    return AirCAMERA_1020.capture_photo_buff
end


--关闭AirCAMERA_1020摄像头

--返回值：成功返回true，失败返回false
function AirCAMERA_1020.close()    
    --如果摄像头还没有打开，直接返回成功
    if not AirCAMERA_1020.opend then
        log.info("AirCAMERA_1020.close ok", "no open, needn't close")
        return true
    end

    --关闭摄像头
    camera.close(AirCAMERA_1020.id)

    --释放存储照片数据的zbuff内存
    if AirCAMERA_1020.capture_photo_buff ~= nil then
        AirCAMERA_1020.capture_photo_buff:free()
        AirCAMERA_1020.capture_photo_buff = nil
    end

    --复位摄像头已经成功打开的标志
    AirCAMERA_1020.opend = false

    return true
end


return AirCAMERA_1020

