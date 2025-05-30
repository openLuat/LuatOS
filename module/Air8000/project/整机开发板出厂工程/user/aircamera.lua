local aircamera = {}

require "gc0310"

local taskName = "SPI_CAMERA"
local TEST_MODE = 0 -- 写1 演示扫码（使用摄像头对二维码、条形码或其他类型的图案进行扫描和识别），0 演示拍照
local scan_pause = true -- 扫码启动与停止标志位
local done_with_close = false -- true 结束后关闭摄像头
local uartid = 1 -- 根据实际设备选取不同的uartid
local cspiId = 1 -- 摄像头使用SPI1、I2C0
local i2cId = 0
local camera_id 
local run_state = 0
-- 初始化UART
local result = uart.setup(uartid, -- 串口id
115200, -- 波特率
8, -- 数据位
1 -- 停止位
)



-- 初始化摄像头
local rawbuff, err = zbuff.create(60 * 1024, 0, zbuff.HEAP_AUTO) -- gc03a
if rawbuff == nil then
    log.info(err)
end

local function aircamera_run()
    lcd.clear()    
    sys.wait(500)
    gpio.setup(147, 1, gpio.PULLUP) -- camera的供电使能脚
    gpio.setup(153, 1, gpio.PULLUP) -- 控制camera电源的pd脚
    gpio.setup(24, 1, gpio.PULLUP)  -- i2c工作的电压域
    gpio.setup(164, 1, gpio.PULLUP) -- 因为I2C 和 音频公用，如果不打开，会造成无法工作
    log.info("摄像头启动")
    gpio.setup(153, 0) -- PD拉低
    camera_id = gc0310Init(cspiId, i2cId, 25500000, TEST_MODE, TEST_MODE)
    camera.stop(camera_id) -- 暂停摄像头捕获数据。仅停止了图像捕获，未影响预览功能。
    camera.preview(camera_id, true) -- 打开LCD预览功能（直接将摄像头数据输出到LCD）
    camera.start(camera_id)
    log.info("start ok")
    if done_with_close then
        camera.close(camera_id)
    else
        camera.stop(camera_id)
    end

    log.info(rtos.meminfo("sys"))
    log.info(rtos.meminfo("psram"))

end

-- 启动任务时传入依赖

function aircamera.run()
    if run_state == 0 then
        sysplus.taskInitEx(aircamera_run,taskName)
        run_state = 1
    end

    while true do
        sys.wait(30)
        if run_state == 0 then    -- 等待结束
            return true
        end
    end
end

return aircamera