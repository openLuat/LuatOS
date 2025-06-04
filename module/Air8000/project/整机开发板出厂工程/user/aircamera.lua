local aircamera = {}

require "gc0310"
local airlcd = require "airlcd"
local httpplus = require "httpplus"
local taskName = "SPI_CAMERA"
local TEST_MODE = 0
local scan_pause = true -- 扫码启动与停止标志位
local done_with_close = false -- true 结束后关闭摄像头
local uartid = 1 -- 根据实际设备选取不同的uartid
local cspiId = 1 -- 摄像头使用SPI1、I2C0
local i2cId = 0
local scan_end = ""
local camera_flag = 0
local send_end = ""
local camera_id 
local run_state = 0
local camera_capture_flag = 0
-- 初始化UART
local result = uart.setup(uartid, -- 串口id
115200, -- 波特率
8, -- 数据位
1 -- 停止位
)

camera.on(0, "scanned", function(id, str)
    if type(str) == 'string' then
        log.info("扫码结果", str)
        scan_end = str
        if TEST_MODE == 1 then
            camera.stop(camera_id)
            camera.preview(camera_id, false)
            TEST_MODE = 0
        end
    elseif str == false then
        log.error("摄像头没有数据")
    else
        log.info("摄像头数据", str)
        sys.publish("capture done", true)
    end
end)



local function HTTP_SEND_FILE()
    send_end = "照片上传中.."
    local opts = {
        url = "http://upload.air32.cn/api/upload/jpg", -- 必选, 目标URL
        method = "POST", -- 可选,默认GET, 如果有body,files,forms参数,会设置成POST
        headers = {}, -- 可选,自定义的额外header
        bodyfile="/ram/testcamera.jpg",   -- 可选,文件上传,若存在本参数,会强制以multipart/form-data形式上传
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
        log.info("发送完了")
        send_end = "照片已上传"
    --     mobile.flymode(0,true) --进入psm+前进入飞行模式，唤醒后需要主动退出
    --     pm.dtimerStart(3, realy_sleep_time)  --启动深度休眠定时器
    -- pm.power(pm.WORK_MODE,3)
    end

end


local function aircamera_run()
    lcd.autoFlush(true) 
    lcd.close()
    camera.preview(camera_id, true) -- 打开LCD预览功能（直接将摄像头数据输出到LCD）
    log.info(rtos.meminfo("sys"))
    log.info(rtos.meminfo("psram"))
    if TEST_MODE == 1 then
        log.info("aircamera start scan")
        camera.close(camera_id)
        log.info("摄像头初始化-扫码")
        gpio.setup(153, 1) -- PD拉高
        sys.wait(100)
        gpio.setup(153, 0) -- PD拉低
        sys.wait(500)
        camera_id = gc0310Init(cspiId, i2cId, 25500000, 1, 1)  -- 最后两个1 ，是默认按照扫码始化
        sys.wait(100)
        camera.start(camera_id)  -- 开始扫码
    end
    while true do
        if TEST_MODE == 0 then
            camera.close(camera_id)
            break
        end
        sys.wait(30)
    end
end

-- 启动任务时传入依赖
function aircamera.init()
    log.info("aircamera_run inint")
    gpio.setup(147, 1, gpio.PULLUP) -- camera的供电使能脚
    gpio.setup(153, 1, gpio.PULLUP) -- 控制camera电源的pd脚
    gpio.setup(24, 1, gpio.PULLUP)  -- i2c工作的电压域
    gpio.setup(164, 1, gpio.PULLUP) -- air8000 整机开发板因为I2C 和 解码芯片公用，如果不打开，会由于解码芯片对地，造成I2C无法工作
    log.info("摄像头初始化")
    gpio.setup(153, 0) -- PD拉低
    sys.wait(500)
    camera_id = gc0310Init(cspiId, i2cId, 25500000, 0, 0)  -- 最后两个0 ，是默认按照拍照初始化
end

local function aircamera_ui()
    -- lcd.clear()

    if TEST_MODE ==0 then
        lcd.clear(_G.bkcolor)    
        lcd.autoFlush(false) 
        lcd.setFont(lcd.font_opposansm12_chinese) -- 具体取值可参考api文档的常量表
        lcd.drawStr(0,80,"本demo 展示摄像头拍照应用，请点击下面的按钮进行功能展示")
        lcd.showImage(120,100,"/luadb/next.jpg")
        lcd.drawStr(0,180,"点击上方按钮将对二维码,一维码进行扫描")
        lcd.drawStr(0,200,"扫描成功后，自动退出，并显示在下方")
        lcd.drawStr(80,220,scan_end)



        lcd.showImage(120,240,"/luadb/next.jpg")
        lcd.drawStr(0,320,"点击上方按钮将进行拍照，点击屏幕后，会将照片上传,并可以在:")
        lcd.drawStr(0,340,"https://www.air32.cn/upload/data/这里看到你拍的照片"..send_end)
        lcd.drawStr(0,365,send_end)

        lcd.showImage(120,360,"/luadb/back.jpg")
        lcd.drawStr(100,440,"点击上方按钮将返回主界面")
        lcd.flush()
    elseif TEST_MODE == 1 or TEST_MODE == 2 then
        aircamera_run()
    elseif TEST_MODE == 3 then
        TEST_MODE = 0
        return true
    end
    return false
end

function aircamera.run()
    log.info("aircamera.run")
    while true do
        if aircamera_ui() then
            return true
        end
        sys.wait(30)
    end
end

function send_file_task()
    if camera_capture_flag == 0 then
        log.info("aircamera send_file_task1")
        camera_capture_flag = 1
        log.info("摄像头初始化-拍照")
        camera.close(camera_id)
        gpio.setup(153, 1) -- PD拉高
        sys.wait(100)
        gpio.setup(153, 0) -- PD拉低
        sys.wait(500)
        camera_id = gc0310Init(cspiId, i2cId, 25500000, 0, 0)  -- 最后两个1 ，是默认按照扫码始化
        sys.wait(100)
        local res= camera.capture(camera_id, "/ram/testcamera.jpg", 95)
        log.info("aircamera send_file_task1 res",res)
        sys.waitUntil("capture done", 30000)
        camera.preview(camera_id, false)
        TEST_MODE = 0
        camera_capture_flag = 0
        HTTP_SEND_FILE()
    end
end


function aircamera.tp_handal(x,y,event)       -- 判断是否需要停止播放
    if TEST_MODE == 0 then
        if x > 120 and  x < 200 and y > 100  and  y < 180 then
            TEST_MODE = 1
        elseif x > 120 and  x < 200 and y > 240  and  y < 320 then
            TEST_MODE = 2
        elseif x > 120 and  x < 200 and y > 360  and  y < 440 then
            TEST_MODE = 3
        end
    elseif TEST_MODE == 2 then
        sys.taskInit(send_file_task, "send_file_task")     
    end
end

return aircamera