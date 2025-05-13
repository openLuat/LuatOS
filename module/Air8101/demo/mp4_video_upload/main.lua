
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "Air8101_VideoRecord_SDSave_OSSUpload"
VERSION = "1.0.0"

-- sys库是标配
_G.sys = require("sys")
httpplus = require "httpplus"

--[[
注意：B10开发板需要SD_3.3V和SWD3.3V短接
]]

-- 特别提醒, 由于FAT32是DOS时代的产物, 文件名超过8个字节是需要额外支持的(需要更大的ROM)
-- 例如 /sd/boottime 是合法文件名, 而/sd/boot_time就不是合法文件名, 需要启用长文件名支持.

local camera_id = camera.USB -- 设置摄像头类型为USB摄像头

-- 配置USB摄像头参数
local usb_camera_table = {
    id = camera_id,      -- 摄像头ID
    sensor_width = 1280, -- 摄像头传感器宽度为1280像素
    sensor_height = 720, -- 摄像头传感器高度为720像素
    usb_port = 1         -- 设置USB摄像头端口为1，Air8101系列支持1、2、3、4端口
}

-- 配置阿里云OSS请求参数（表单上传、签名）
-- 需要修改为自己的阿里云OSS参数
local opts = {
    url = "xxxxxxxx.oss-cn-hangzhou.aliyuncs.com", -- 必选, 目标URL
    method = "POST", -- 可选, 默认GET, 如果有body, files, forms参数, 会设置成POST
    headers = {}, -- 可选,自定义的额外header
    files = {file = "/sd/abc.mp4"}, -- 可选, 键值对的形式, 文件上传, 若存在本参数, 会强制以multipart/form-data形式上传
    forms = {
        key = "vedio/abc.mp4",
        policy = "xxxxxxxxxxx==",
        OSSAccessKeyId = "xxxxxxxxxxx",
        Signature = "xxxxxxxxxx="
    }, -- 可选,键值对的形式,表单参数,若存在本参数,如果不存在files,按application/x-www-form-urlencoded上传
}

-- 联网函数, 可自行删减
sys.taskInit(function()
    -----------------------------
    -- 统一联网函数, 可自行删减
    ----------------------------
    if wlan and wlan.connect then
        -- WiFi 联网, Air8101系列均支持
        -- 需要修改为自己的WiFi名称和密码，AP频段使用2.4Ghz频段，不支持5Ghz频段。
        local ssid = "HONOR_100_Pro"  -- WiFi名称
        local password = "12356789" -- WiFi密码
        log.info("WiFi", ssid, password)

        wlan.init() -- 初始化wlan
        wlan.connect(ssid, password, 1) -- 设备作为STA模式连接到指定的WiFi
        --等待WiFi联网结果，WiFi联网成功后，内核固件会产生一个"IP_READY"消息
        local result, data = sys.waitUntil("IP_READY") -- 等待"IP_READY"消息，并返回等待结果和数据
        log.info("wlan", "IP_READY", result, data)
    end
    log.info("已联网")
    sys.publish("net_ready") -- 发布一个"net_ready"消息，表示网络已就绪
end)

local rtos_bsp = rtos.bsp() -- 获取模组型号，此代码中应为 Air8101

-- 定义Air8101系列的SPI总线编号（spi_id）、片选引脚（pin_cs）以及文件系统类型（tp）
local function fatfs_spi_pin()

    if rtos_bsp == "Air8101" then
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
        spi.setup(spi_id, nil, 0, 0, 8, 400 * 1000) -- 初始化SPI
        gpio.setup(pin_cs, 1) -- 设置pin_cs为输出模式
    end

    -- lua内存
    log.info("lua", rtos.meminfo())
    -- sys内存
    log.info("sys", rtos.meminfo("sys"))

-------------------------------挂载SD卡---------------------------------------------
-----------------------------------------------------------------------------------
    local mount_result = fatfs.mount(tp or fatfs.SPI, "/sd", spi_id, pin_cs, 24 * 1000 * 1000) -- 挂载SD卡
    log.info("fatfs", "mount", mount_result) -- 打印挂载结果
    local data, err = fatfs.getfree("/sd") -- 获取SD卡剩余空间信息
    if data then
        -- table: 若成功会返回table, 否则返回nil
        -- table 中包含 total_sectors（总扇区数量）, free_sectors（空闲扇区数量）, total_kb（总字节数,单位kb）, free_kb（空闲字节数, 单位kb）
        log.info("fatfs", "getfree", json.encode(data))
    else
        -- err: 导致失败的底层返回值
        log.info("fatfs", "err", err)
    end

--------------------------------视频录制--------------------------------------------
-----------------------------------------------------------------------------------
    result = camera.init(usb_camera_table) -- 初始化指定的camera
    log.info("摄像头初始化", result) -- 打印初始化结果
    if(result == 0) then -- 0表示初始化成功
        camera.start(camera_id) -- 开始指定的camera
        --开始mp4录制
        camera.capture(camera_id, "/sd/abc.mp4", 1)
        sys.wait(20000) -- 录制时长
        --结束MP4录制
        camera.stop(camera_id) -- 停止指定的camera
        log.info("保存成功") -- 打印保存成功结果
    end
    camera.close(camera_id) -- 关闭指定的camera，释放相应的IO资源
    log.info("摄像头关闭") -- 打印关闭摄像头结果

--------------------------------阿里云OSS上传----------------------------------------
------------------------------------------------------------------------------------
    local code, resp = httpplus.request(opts) -- 执行HTTP请求
    log.info("http", code) -- 打印服务器返回的状态码
    -- 返回值resp的说明
    -- 情况1, code >= 100 时, resp会是个table, 包含2个元素
    if code ~= nil and code >= 100 then
        -- headers, 是个table
        log.info("http", "headers", json.encode(resp.headers))
        -- body, 是个zbuff
        -- 通过query函数可以转为lua的string
        log.info("http", "body", resp.body:query())
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
