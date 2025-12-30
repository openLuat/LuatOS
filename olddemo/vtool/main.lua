
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "vtool"
VERSION = "1.0.0"

httpplus = require "httpplus"


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
        gpio.setup(13, 1, gpio.PULLUP)
        return 0, 3, fatfs.SDIO
    else
        log.info("main", "bsp not support")
        return
    end
end

sys.taskInit(function()
    sys.wait(1000)
    -- fatfs.debug(1) -- 若挂载失败,可以尝试打开调试信息,查找原因

    gpio.set(13, 1)

    -- 此为spi方式
    local spi_id, pin_cs,tp = fatfs_spi_pin() 
    if tp and tp == fatfs.SPI then
        -- 仅SPI方式需要自行初始化spi, sdio不需要
        spi.setup(spi_id, nil, 0, 0, 8, 400 * 1000)
        gpio.setup(pin_cs, 1)
    end
    log.info("fatfs", "mounting...")
    fatfs.mount(tp or fatfs.SPI, "/sd", spi_id, pin_cs, 24 * 1000 * 1000)
    log.info("fatfs", "mounted")

    local data, err = fatfs.getfree("/sd")
    if data then
        log.info("fatfs", "getfree", json.encode(data))
    else
        log.info("fatfs", "err", err)
    end

    local pnum = 27
    local init_qp = 40
    local i_qp_max = 28
    local p_qp_max = 28
    local imb_bits = 3
    local pmb_bits = 3

    camera.config(0, camera.CONF_H264_QP_INIT, init_qp)
    camera.config(0, camera.CONF_H264_QP_I_MAX, i_qp_max)
    camera.config(0, camera.CONF_H264_QP_P_MAX, p_qp_max)
    camera.config(0, camera.CONF_H264_IMB_BITS, imb_bits)
    camera.config(0, camera.CONF_H264_PMB_BITS, pmb_bits)

    log.info("开始测试==================")
    vtool.h264_encoder_init()
    vtool.h264_encoder_start()
    local dst = "/sd/test.mp4"
    local mp4 = vtool.mp4create(dst, 1280, 720, 15)

    log.info("vtool", "开始写入jpeg文件")
    -- 从0.jpg, 写到 4.jpg
    for i = 0, 4 do
        local filename = string.format("/sd/C8C2C68CACB8_904_1.mp4.%d.jpg", i)
        log.info("vtool", "写入文件", filename)
        local ret = vtool.mp4write_jpeg(mp4, filename)
        log.info("vtool", "写入结果", ret)
        sys.wait(70)
    end

    sys.wait(1000)

    vtool.mp4close(mp4)
    log.info("vtool", "测试完成, 文件保存在", dst)
    -- 打印文件大小
    log.info("vtool", "test.mp4 size", io.fileSize(dst))

    vtool.h264_encoder_deinit()

    wlan.init()
    wlan.connect("luatos1234", "12341234")

    sys.waitUntil("IP_READY")
    httpplus.request({
        url = "http://upload.air32.cn/api/upload/mp4",
        method = "POST",
        bodyfile = dst
    })
    log.info("执行结束------")
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
