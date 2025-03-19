
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "usb_cam_mp4"
VERSION = "1.0.0"

-- sys库是标配
_G.sys = require("sys")


-- 特别提醒, 由于FAT32是DOS时代的产物, 文件名超过8个字节是需要额外支持的(需要更大的ROM)
-- 例如 /sd/boottime 是合法文件名, 而/sd/boot_time就不是合法文件名, 需要启用长文件名支持.


local camera_id = camera.USB

local usb_camera_table = {
    id = camera_id,
    sensor_width = 1280,
    sensor_height = 720,
    usb_port = 1
}



local rtos_bsp = rtos.bsp()

-- spi_id,pin_cs
local function fatfs_spi_pin()
    if rtos_bsp == "AIR101" then
        return 0, pin.PB04
    elseif rtos_bsp == "AIR103" then
        return 0, pin.PB04
    elseif rtos_bsp == "AIR105" then
        return 2, pin.PB03
    elseif rtos_bsp == "ESP32C3" then
        return 2, 7
    elseif rtos_bsp == "ESP32S3" then
        return 2, 14
    elseif rtos_bsp == "EC618" then
        return 0, 8
    elseif string.find(rtos_bsp,"EC718") then
        return 0, 8
    elseif string.find(rtos_bsp,"Air810") then
        return 0, 3, fatfs.SDIO
    else
        log.info("main", "bsp not support")
        return
    end
end

sys.taskInit(function()
    sys.wait(1000)
    -- fatfs.debug(1) -- 若挂载失败,可以尝试打开调试信息,查找原因

    -- 此为spi方式
    local spi_id, pin_cs,tp = fatfs_spi_pin()
    if tp and tp == fatfs.SPI then
        -- 仅SPI方式需要自行初始化spi, sdio不需要
        spi.setup(spi_id, nil, 0, 0, 8, 400 * 1000)
        gpio.setup(pin_cs, 1)
    end

      -- lua内存
    log.info("lua", rtos.meminfo())
    -- sys内存
    log.info("sys", rtos.meminfo("sys"))

    fatfs.mount(tp or fatfs.SPI, "/sd", spi_id, pin_cs, 24 * 1000 * 1000)

    local data, err = fatfs.getfree("/sd")
    if data then
        log.info("fatfs", "getfree", json.encode(data))
    else
        log.info("fatfs", "err", err)
    end



    --初始化摄像头
    result=camera.init(usb_camera_table)
    log.info("摄像头初始化", result)
    if(result==0) then
        camera.start(camera_id)
        --开始mp4录制
        camera.capture(camera_id, "/sd/abc.mp4", 1)
        sys.wait(25000)

        --结束MP4录制
        camera.stop(camera_id)

        log.info("保存成功")
    end
    camera.close(camera_id)
    -- #################################################

end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
