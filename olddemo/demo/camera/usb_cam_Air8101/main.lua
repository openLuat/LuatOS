PROJECT = "usb_cam_demo"
VERSION = "1.0.0"

-- log.style(1)

httpplus = require "httpplus"

local uartid = 1 -- 根据实际设备选取不同的uartid
local uartBaudRate = 115200 -- 串口波特率
local uartDatabits = 8 -- 串口数据位
local uartStopBits = 1 -- 串口停止位

local lcd_use_buff = true -- 是否使用缓冲模式, 提升绘图效率，占用更大内存
local port, pin_reset, bl = lcd.RGB, 36, 25

local rtos_bsp = rtos.bsp() -- 获取硬件bsp型号

-- 根据模块型号返回ADC引脚编号的函数
-- 如果模块为Air8101，返回引脚14；否则记录错误信息并返回255
function adc_pin()
    if rtos_bsp == "Air8101" then
        return 14
    else
        log.info("模块型号: ", rtos_bsp)
        log.info("main", "bsp not Air8101!!!")
        return 255
    end
end

local adc_pin_14 = adc_pin() -- 获取ADC引脚编号

-- 如果获取到的ADC引脚编号有效且不等于255，则打开该ADC引脚
if adc_pin_14 and adc_pin_14 ~= 255 then adc.open(adc_pin_14) end

-- -- 联网函数, 可自行删减
-- sys.taskInit(function()
--     -----------------------------
--     -- 统一联网函数, 可自行删减
--     ----------------------------
--     if wlan and wlan.connect then
--         -- wifi 联网, Air8101系列均支持
--         local ssid = "HONOR_100_Pro"
--         local password = "12356789"
--         log.info("wifi", ssid, password)

--         wlan.init()
--         wlan.connect(ssid, password, 1)
--         --等待WIFI联网结果，WIFI联网成功后，内核固件会产生一个"IP_READY"消息
--         local result, data = sys.waitUntil("IP_READY")
--         log.info("wlan", "IP_READY", result, data)
--     end
--     log.info("已联网")
--     sys.publish("net_ready")
-- end)

-----------------------------初始化LCD屏幕------------------------------------

-- -- Air8101开发板配套LCD屏幕 分辨率800*480
-- lcd.init("h050iwv",
--         {port = port, pin_dc = 0xff, pin_pwr = bl, pin_rst = pin_reset,
--         direction = 0, w = 800, h = 480, xoffset = 0, yoffset = 0})

-- -- Air8101开发板配套LCD屏幕 分辨率1024*600
-- lcd.init("hx8282",
--         {port = port,pin_pwr = bl, pin_rst = pin_reset,
--         direction = 0,w = 1024,h = 600,xoffset = 0,yoffset = 0})

-- -- Air8101开发板配套LCD屏幕 分辨率720*1280
-- lcd.init("nv3052c",
--         {port = port,pin_pwr = bl, pin_rst = pin_reset,
--         direction = 0,w = 720,h = 1280,xoffset = 0,yoffset = 0})

-- Air8101开发板配套LCD屏幕 分辨率480*854
-- lcd.init("st7701sn",
--         {port = port,pin_pwr = bl, pin_rst = pin_reset,
--         direction = 0,w = 480,h = 854,xoffset = 0,yoffset = 0})

------------------------------------------------------------------------------
-- 如果显示颜色相反，请解开下面一行的注释，关闭反色
-- lcd.invoff()

-- 初始化串口
uart.setup(uartid, uartBaudRate, uartDatabits, uartStopBits)

local camera_id = camera.USB -- 选择USB摄像头
local usb_port = 1 -- USB摄像头端口号

-- 设置摄像头参数，30W-200W像素
-- 配置1：1280 * 720 分辨率
-- 配置2：864 * 480 分辨率
-- 配置3：800 * 480 分辨率
-- 配置4：640 * 480 分辨率
local usb_camera_set = {
    { id = camera_id, sensor_width = 1280, sensor_height = 720 , usb_port = usb_port},   -- 配置1
    { id = camera_id, sensor_width = 864,  sensor_height = 480 , usb_port = usb_port},   -- 配置2
    { id = camera_id, sensor_width = 800,  sensor_height = 480 , usb_port = usb_port},   -- 配置3
    { id = camera_id, sensor_width = 640,  sensor_height = 480 , usb_port = usb_port}    -- 配置4
}
local usb_camera_table = usb_camera_set[1] -- 选择摄像头参数

-- 开启摄像头画面预览
-- camera.config(0, camera.CONF_PREVIEW_ENABLE, 1)
-- 假如预览画面方向有问题，配置下画面旋转
-- camera.config(0, camera.CONF_PREVIEW_ROTATE, camera.ROTATE_90)

-- 注册摄像头回调函数
camera.on(camera_id, "scanned", function(id, str)
    log.info("scanned", id, str)
    if type(str) == 'string' then
        log.info("扫码结果", str)
    elseif str == false then
        log.error("摄像头没有数据")
    else
        log.info("摄像头数据", str)
        sys.publish("capture done", true)
    end
end)

local camera_init_ok = false -- 定义一个局部变量camera_init_ok，用于记录摄像头初始化是否成功。

-- 按键处理函数
-- 通过检测ADC14的电压值来判断特定按键（KEY6、KEY5、KEY3）是否被按下，并根据按键的操作来控制USB摄像头的行为。
sys.taskInit(function()
    while true do
        -- 当检测到ADC14的电压值在1300到2000之间时，认为KEY6被按下。
        -- 此时，代码会切换USB摄像头的端口号到下一个端口。
        if adc.get(adc_pin_14) < 2000 and adc.get(adc_pin_14) > 1300 then
            log.info("ADC14电压大于1.3V,小于2.0V")
            log.info("KEY6按下")
            if usb_camera_table.usb_port == 4 then
                log.info("已经是最后一个端口了")
            else
                usb_camera_table.usb_port = usb_camera_table.usb_port + 1
                camera.close(camera_id)
                camera_init_ok = camera.init(usb_camera_table)
                log.info("摄像头初始化", camera_init_ok)
                log.info("USB_PORT端口切换: ", usb_camera_table.usb_port)
            end
            while true do
                if adc.get(adc_pin_14) > 2000 then
                    break
                end
            end
        end
        -- 当检测到ADC14的电压值在1000到1300之间时，认为KEY5被按下。
        -- 此时，代码会切换USB摄像头的端口号到上一个端口。
        if adc.get(adc_pin_14) < 1300 and adc.get(adc_pin_14) > 1000 then
            log.info("ADC14电压大于1.0V,小于1.3V")
            log.info("KEY5按下")
            if usb_camera_table.usb_port == 1 then
                log.info("已经是第一个端口了")
            else
                usb_camera_table.usb_port = usb_camera_table.usb_port - 1
                camera.close(camera_id)
                camera_init_ok = camera.init(usb_camera_table)
                log.info("摄像头初始化", camera_init_ok)
                log.info("USB_PORT端口切换: ", usb_camera_table.usb_port)
            end
            while true do
                if adc.get(adc_pin_14) > 2000 then
                    break
                end
            end
        end
        -- 当检测到ADC14的电压值小于100时，认为KEY3被按下。
        -- 此时，代码会发布一个名为"PRESS"的消息，携带参数"KEY3"，在这个main.lua文件中用于触发拍照功能。
        if adc.get(adc_pin_14) < 100 then
            log.info("ADC14电压小于1.0V")
            log.info("KEY3按下")
            sys.publish("PRESS", "KEY3")
            while true do
                if adc.get(adc_pin_14) > 2000 then
                    break
                end
            end
        end
        sys.wait(100)
    end
end)

-- 创建zbuff
local rawbuff, err = zbuff.create(200 * 1024, 0, zbuff.HEAP_PSRAM)

-- 初始化摄像头并处理拍照和上传图片的操作
sys.taskInit(function()
    -- -- 开启缓冲区, 刷屏速度会加快, 但也消耗2倍屏幕分辨率的内存
    -- lcd.setupBuff(nil, true) -- 使用sys内存, 只需要选一种
    -- lcd.autoFlush(false)
    -- lcd.clear()

    if rawbuff == nil then
        while true do
            sys.wait(1000)
        end
        log.info("zbuff创建失败", err)
    end

    camera_init_ok = camera.init(usb_camera_table)
    log.info("摄像头初始化", camera_init_ok)
    log.info(rtos.meminfo("sys")) -- 打印系统内存信息
    log.info(rtos.meminfo("psram")) -- 打印psram内存信息

    while 1 do
        local result, param = sys.waitUntil("PRESS", 5000)
        log.info("PRESS", result, param)
        if param == "KEY3" and camera_init_ok == 0 then
            camera.start(camera_id) --开始指定的camera
            -- camera.capture(camera_id, "/abc.jpg", 1) --camera拍照并保存到指定路径
            camera.capture(camera_id, rawbuff, 1)
            result, data = sys.waitUntil("capture done", 30000)
            log.info(rawbuff:used())
            camera.stop(camera_id) --停止指定的camera
            -- lcd.showImage(0, 0, "/abc.jpg") --在屏幕上显示照片
            -- lcd.flush()
            -- camera.close(camera_id)	--关闭指定的camera，释放相应的IO资源；完全关闭摄像头才用这个
            -- rawbuff:resize(200 * 1024)

            -- 通过串口发送图片数据
            -- uart.tx(uartid, rawbuff) --找个能保存数据的串口工具保存成文件就能在电脑上看了, 格式为JPG

            -- 通过WIFI网络上传到服务器查看
            -- 上传到upload.air32.cn, 数据访问页面是 https://www.air32.cn/upload/data/
            -- local code, resp = httpplus.request({
            --     url = "http://upload.air32.cn/api/upload/jpg",
            --     method = "POST",
            --     body = rawbuff
            -- })
            -- log.info("http", code)

            -- -- 打印内存信息, 调试用
            -- log.info("sys", rtos.meminfo())
            -- log.info("sys", rtos.meminfo("sys"))
            -- log.info("psram", rtos.meminfo("psram"))
        elseif param == "KEY3" then
            log.info("KEY3按下，但是摄像头初始化失败")
        end
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
