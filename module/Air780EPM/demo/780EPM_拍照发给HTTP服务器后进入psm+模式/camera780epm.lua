-- 实际使用时选1个就行
-- require "bf30a2"
require "gc032a"
-- require "gc0310"
httpplus = require "httpplus"

gpio.setup(2, 1) -- GPIO2打开给camera电源供电
gpio.setup(28, 1) -- 1.2版本 GPIO28打开给lcd电源供电
gpio.setup(29, 1) -- 1.3版本 GPIO29打开给lcd电源供电
local sleep_time = 1
local period = 60*60*1000
local realy_sleep_time = sleep_time*period
gpio.setup(14, nil)
gpio.setup(15, nil)

local reason, slp_state = pm.lastReson()  --获取唤醒原因
log.info("wakeup state", pm.lastReson())

if slp_state > 0 then
    mobile.flymode(0,false) -- 退出飞行模式，进入psm+前进入飞行模式，唤醒后需要主动退出
end

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


------------------------------------
------------ 初始化 LCD ------------
------------------------------------
-- 根据不同的BSP返回不同的值
-- spi_id,pin_reset,pin_dc,pin_cs,bl
local function lcd_pin()
    local rtos_bsp = rtos.bsp()
    if string.find(rtos_bsp,"780EPM") then
        return lcd.HWID_0, 36, 0xff, 0xff, 0xff -- 注意:EC718P有硬件lcd驱动接口, 无需使用spi,当然spi驱动也支持
    else
        log.info("main", "没找到合适的cat.1芯片",rtos_bsp)
        return
    end
end
local spi_id, pin_reset, pin_dc, pin_cs, bl = lcd_pin()
if spi_id ~= lcd.HWID_0 then
    spi_lcd = spi.deviceSetup(spi_id, pin_cs, 0, 0, 8, 20 * 1000 * 1000, spi.MSB, 1, 0)
    port = "device"
else
    port = spi_id
end


lcd.init("st7796", {
    port = port,
    pin_dc = pin_dc,
    pin_pwr = bl,
    pin_rst = pin_reset,
    direction = 0,
    -- direction0 = 0x00,
    w = 320,
    h = 480,
    xoffset = 0,
    yoffset = 0,
    sleepcmd = 0x10,
    wakecmd = 0x11,
})



-- 将拍好的照片发送到HTTP服务器里保存，
-- 当前测试服务器可以在https://www.air32.cn/upload/data/这里看到你拍的照片

local function HTTP_SEND_FILE()

    local opts = {
        url = "http://upload.air32.cn/api/upload/jpg", -- 必选, 目标URL
        method = "POST", -- 可选,默认GET, 如果有body,files,forms参数,会设置成POST
        headers = {}, -- 可选,自定义的额外header
        files = {file= "/testcamera.jpg"},   -- 可选,文件上传,若存在本参数,会强制以multipart/form-data形式上传
        forms = {}, -- 可选,表单参数,若存在本参数,如果不存在files,按application/x-www-form-urlencoded上传
        -- body  = "abc=123",-- 可选,自定义body参数, 字符串/zbuff/table均可, 但不能与files和forms同时存在
        debug = false, -- 可选,打开调试日志,默认false
        try_ipv6 = false, -- 可选,是否优先尝试ipv6地址,默认是false
        adapter = nil, -- 可选,网络适配器编号, 默认是自动选
        timeout = 30, -- 可选,读取服务器响应的超时时间,单位秒,默认30
        -- bodyfile = "/testCamera.jpg" -- 可选,直接把文件内容作为body上传, 优先级高于body参数
    }

    local code, resp = httpplus.request(opts)
    log.info("http", code)
    -- 返回值resp的说明
    -- 情况1, code >= 100 时, resp会是个table, 包含2个元素
    if code >= 100 then
        -- headers, 是个table
        log.info("http", "headers", json.encode(resp.headers))
        -- body, 是个zbuff
        -- 通过query函数可以转为lua的string
        log.info("http", "headers", resp.body:query())
        log.info("发送完了，进PSM+吧")
    --     mobile.flymode(0,true) --进入psm+前进入飞行模式，唤醒后需要主动退出
    --     pm.dtimerStart(3, realy_sleep_time)  --启动深度休眠定时器
    -- pm.power(pm.WORK_MODE,3)
    end

end

sys.taskInit(function()
    sys.wait(5000)
    log.info("摄像头启动")
    -- spi的id和摄像头的id
    local cspiId, i2cId = 1, 1
    local camera_id
    -- 配置iic
    i2c.setup(i2cId, i2c.FAST)

    gpio.setup(5, 0) -- PD拉低
    camera_id = gc032aInit(cspiId, i2cId, 24000000, SCAN_MODE, SCAN_MODE)
    camera.stop(camera_id)
    camera.preview(camera_id, true)--摄像头预览打开

    log.debug("摄像头拍照")
    -- 同名照片会被覆盖，所以这里拍照完保存在文件系统中的照片不用删除，
    -- 但是如果你的照片名字是按一定规律排序的，一定记得删除
    -- 后面的参数是照片质量，如果感觉默认的1质量不太好，可以换成2或者3
    -- 但是，2和3需要非常多非常多的psram,能不用还是不用
    camera.capture(camera_id, "/testcamera.jpg", 1)

    result, data = sys.waitUntil("capture done", 30000)

    -- camera.close(camera_id)	--完全关闭摄像头才用这个
    camera.stop(camera_id) --如果没有低功耗需求，就打开本句，屏蔽上面这句

    HTTP_SEND_FILE()

end)
