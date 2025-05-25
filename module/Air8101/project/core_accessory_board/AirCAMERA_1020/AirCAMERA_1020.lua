
--使用正式发布的LuatOS-SoC_V1003_Air8101.soc可以正常运行此demo
--使用最新的固件无法正常运行，等待解决



local AirCAMERA_1020 =
{
    id = camera.DVP,
    -- capture_photo_buff：拍照使用的zbuff缓冲区
    -- opend：是否已经成功打开
}

local function camera_scan_cbfunc(id, str)
    log.info("camera_scan_cbfunc", id, str)
    if type(str) == 'string' then
        log.info("scan code result", str)
    elseif str == false then
        log.error("no data")
    else
        log.info("capture photo data", str)
        sys.publish("AirCAMERA_1020_CAPTURE_IND", true)
    end
end

--width:照片宽，默认1280
--height：照片高，默认720
function AirCAMERA_1020.open(width, height)
    width = width or 1280
    height = height or 720

    if width*height>1280*720 then
        log.error("AirCAMERA_1020.open error", "invalid width or height", width, height)
        return false
    end

    if AirCAMERA_1020.capture_photo_buff==nil then
        AirCAMERA_1020.capture_photo_buff = zbuff.create(200 * 1024, 0, zbuff.HEAP_PSRAM)
        if AirCAMERA_1020.capture_photo_buff == nil then
            log.error("AirCAMERA_1020.open error", "malloc mem fail")
            return false
        end
    end

    if not camera.init({id = AirCAMERA_1020.id, sensor_width = width, sensor_height = height}) then
        log.error("AirCAMERA_1020.open error", "camera.init fail")
        AirCAMERA_1020.capture_photo_buff:free()
        AirCAMERA_1020.capture_photo_buff = nil
        return false
    end

    camera.on(AirCAMERA_1020.id, "scanned", camera_scan_cbfunc)

    AirCAMERA_1020.opend = true

    return true
end




--必须在task中使用
function AirCAMERA_1020.capture()
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

    if not AirCAMERA_1020.opend then
        log.error("AirCAMERA_1020.capture error", "camera isn't opend")
        return false
    end

    if not camera.start(AirCAMERA_1020.id) then
        log.error("AirCAMERA_1020.capture error", "camera.start fail")
        return false
    end

    if not camera.capture(AirCAMERA_1020.id, AirCAMERA_1020.capture_photo_buff, 1) then
        log.error("AirCAMERA_1020.capture error", "camera.capture sync fail")
        return false
    end

    

    result = sys.waitUntil("AirCAMERA_1020_CAPTURE_IND", 5000)
    log.info("AirCAMERA_1020.capture", "photo size", AirCAMERA_1020.capture_photo_buff:used())
    if not result then
        log.error("AirCAMERA_1020.capture error", "camera.capture async fail")
        return false
    end

    camera.stop(AirCAMERA_1020.id)

    return AirCAMERA_1020.capture_photo_buff
end


function AirCAMERA_1020.close()    
    if not AirCAMERA_1020.opend then
        log.info("AirCAMERA_1020.close ok", "no open, needn't close")
        return true
    end

    camera.close(AirCAMERA_1020.id)

    if AirCAMERA_1020.capture_photo_buff ~= nil then
        AirCAMERA_1020.capture_photo_buff:free()
        AirCAMERA_1020.capture_photo_buff = nil
    end

    AirCAMERA_1020.opend = false

    return true
end



return AirCAMERA_1020

