--[[
1. 本demo可直接在Air8000整机开发板上运行
2. 演示摄像头拍照扫码功能，通过TEST_MODE宏来选择演示的内容。
摄像头使用了如下管脚
[85, "AGPIO4", " PIN85脚, PA供电使能"],
[67, "CAM_SPI_CLK", " PIN67脚, 用作摄像头时钟"],
[66, "CAM_SPI_CS", " PIN66脚, 用作摄像头片选"],
[98, "CAM_MCLK", " PIN98脚, 用于摄像头时钟"],
[52, "GPIO153", " PIN52脚, 控制摄像头开启/关闭"],
[53, "GPIO147", " PIN53脚, 控制摄像头电源"],
[80, "I2C0_SCL", " PIN80脚, 用作摄像头复用"],
[81, "I2C0_SDA", " PIN81脚, 用作摄像头复用"],
[1, "USB_BOOT", " PIN1脚, 用作功能键"],
[16, "UART1_TX", " PIN16脚,初始化串口1"],
[17, "UART1_RX", " PIN17脚,用作输出拍摄的照片"]
3.注意：在air8000整机开发版上，因为es8311/gsensor/lcd_tp触摸/camera 用的都是I2C0(80/81脚)，所以使用此demo时不能同时使用es8311/gsensor/lcd_tp触摸功能
4. 本程序使用逻辑：
4.1 如果TEST_MODE  设置为1 ，程序运行后，点击boot 键，将进行扫码测试，如果解析二维码或者条形码成功，将会打印在luatools 中。
4.2 如果TEST_MODE  设置为0，程序运行后，点击boot 键，将进行拍照测试，并且保存在本地。
]]
PROJECT = "spi_camera_demo"
VERSION = "1.0.0"
-- 实际使用时选1个就行
-- require "bf30a2"
-- require "gc0310"
require "gc032a"
sys = require("sys")
sysplus = require("sysplus")

local taskName = "SPI_CAMERA"
local TEST_MODE = 0 -- 写1 演示扫码（使用摄像头对二维码、条形码或其他类型的图案进行扫描和识别），0 演示拍照
local scan_pause = true -- 扫码启动与停止标志位
local done_with_close = false -- true 结束后关闭摄像头
local uartid = 1 -- 根据实际设备选取不同的uartid
local cspiId = 1 -- 摄像头使用SPI1、I2C0
local i2cId = 0
local camera_id

-- 初始化UART
local result = uart.setup(uartid, -- 串口id
115200, -- 波特率
8, -- 数据位
1 -- 停止位
)

-- 注册摄像头事件回调
camera.on(0, "scanned", function(id, str)
    if type(str) == 'string' then
        log.info("扫码结果", str)
    elseif str == false then
        log.error("摄像头没有数据")
    else
        log.info("摄像头数据", str)
        sys.publish("capture done", true)
    end
end)

-- 初始化按键，这里选取boot键作为功能键
local function press_key()
    log.info("boot press")
    sys.publish("PRESS", true)
end
gpio.setup(0, press_key, gpio.PULLDOWN, gpio.RISING)
gpio.debounce(0, 100, 1)

-- 初始化摄像头
local rawbuff, err = zbuff.create(60 * 1024, 0, zbuff.HEAP_AUTO) -- gc032a
if rawbuff == nil then
    log.info(err)
end
local function device_init()
    i2c.setup(i2cId, i2c.FAST)
    gpio.setup(153, 0) -- PD拉低
    sys.wait(500)
    -- return bf30a2Init(cspiId,i2cId,25500000,TEST_MODE,TEST_MODE)
    -- return gc0310Init(cspiId, i2cId, 25500000, TEST_MODE, TEST_MODE)
    return gc032aInit(cspiId, i2cId, 24000000, TEST_MODE, TEST_MODE)
end

local function main_task()
        sys.wait(500)
        gpio.setup(147, 1, gpio.PULLUP) -- camera的供电使能脚
        gpio.setup(153, 1, gpio.PULLUP) -- 控制camera电源的pd脚
        gpio.setup(24, 1, gpio.PULLUP)          -- 打开内部公用的gsensor，所以需要先打开供电
        gpio.setup(164, 1, gpio.PULLUP)          -- 因为整机开发板的音频i2c 共用，不打开会导致I2C 对地，所以需要打开音频的codec
        sys.wait(4000)
        log.info("摄像头启动")
        local camera_id = device_init()

        if done_with_close then
            camera.close(camera_id)
        else
            camera.stop(camera_id)
        end
        log.info("按下boot开始测试")
        log.info(rtos.meminfo("sys"))
        log.info(rtos.meminfo("psram"))
        while 1 do
            result, data = sys.waitUntil("PRESS", 30000)
            if result == true and data == true then
                if TEST_MODE == 1 then
                    if scan_pause then
                        log.info("启动扫码")
                        if done_with_close then
                            camera_id = device_init()
                        end
                        camera.start(camera_id)
                        scan_pause = false
                        sys.wait(1000)
                        log.info(rtos.meminfo("sys"))
                        log.info(rtos.meminfo("psram"))
                    else
                        log.info("停止扫码")
                        if done_with_close then
                            camera.close(camera_id)
                        else
                            camera.stop(camera_id)
                        end
                        scan_pause = true
                        sys.wait(1000)
                        log.info(rtos.meminfo("sys"))
                        log.info(rtos.meminfo("psram"))
                    end
                else
                    log.debug("摄像头拍照")
                    if done_with_close then
                        camera_id = device_init()
                    end
                    -- 先保存到文件，再上传
                    local save_path = "/ram/capture.jpg"
                    camera.capture(camera_id, save_path, 95)
                    result, data = sys.waitUntil("capture done", 30000)
                    if done_with_close then
                        camera.close(camera_id)
                    else
                        camera.stop(camera_id)
                    end

                    -- 上传服务器
                    local httpplus = require("httpplus")
                    local opts = {
                        url = "http://upload.air32.cn/api/upload/jpg", -- 必选, 目标URL
                        method = "POST", -- 可选,默认GET, 如果有body,files,forms参数,会设置成POST
                        headers = {}, -- 可选,自定义的额外header
                        body = io.readFile("/ram/capture.jpg"), -- 将原始缓冲区中已使用的数据转换为字符串，作为HTTP请求的body内容
                        forms = {}, -- 可选,表单参数,若存在本参数,如果不存在files,按application/x-www-form-urlencoded上传
                        debug = false, -- 可选,打开调试日志,默认false
                        try_ipv6 = false, -- 可选,是否优先尝试ipv6地址,默认是false
                        adapter = nil, -- 可选,网络适配器编号, 默认是自动选
                        timeout = 30, -- 可选,读取服务器响应的超时时间,单位秒,默认30
                    }
                    local code, resp = httpplus.request(opts)
                    if code >= 200 and code < 300 then
                        -- headers, 是个table
                        log.info("http", "headers", json.encode(resp.headers))
                        -- body, 是个zbuff
                        -- 通过query函数可以转为lua的string
                        log.info("http", "headers", resp.body:query())
                        log.info("发送完毕，图片在： https://www.air32.cn/upload/data/jpg/ 中查看")
                    else
                        log.error("上传失败，http code:", code)
                    end
                    rawbuff:resize(60 * 1024)
                    log.info(rtos.meminfo("sys"))
                    log.info(rtos.meminfo("psram"))
                end
            end
        end
end

-- 启动任务时传入依赖
sysplus.taskInitEx(main_task,taskName)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
