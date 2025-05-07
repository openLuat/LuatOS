local AirCam0310 = {}

-- 实际使用时选1个就行
-- require "bf30a2"
-- require "gc032a"
require "gc0310"

local camera_id = 0

AirCam0310.isquit = false

local function oncamfun(id, str)
        if type(str) == 'string' then
            log.info("扫码结果", str)
        elseif str == false then
            log.error("摄像头没有数据")
        else
            log.info("摄像头数据", str)
            sys.publish("capture done", true)
        end
end


    -- 根据不同的BSP返回不同的值
    -- spi_id,pin_reset,pin_dc,pin_cs,bl
local function lcd_pin()
        -- local rtos_bsp = rtos.bsp()
        -- if string.find(rtos_bsp, "Air8000") then
        --     -- if string.find(rtos_bsp, "EC718PM") then
            return lcd.HWID_0, 36, 0xff, 0xff, 25 -- 注意:EC718P有硬件lcd驱动接口, 无需使用spi,当然spi驱动也支持
        -- else
        --     log.info("main", "没找到合适的cat.1芯片", rtos_bsp)
        --     return
        -- end
end

local function air8000epmv13_cam_int()
    gpio.setup(147, 1) -- GPIO147打开给camera电源供电
    -- gpio.setup(28, 1) -- GPIO28打开给lcd电源供电
    gpio.setup(141, 1) -- GPIO28打开给lcd电源供电


    gpio.setup(14, nil)
    gpio.setup(15, nil)

    local getRawStart = false
    local RAW_MODE = 0 -- 写1演示获取原始图像
    -- SCAN_MODE和RAW_MODE都没有写1就是拍照

    camera.on(0, "scanned", oncamfun)

    local rawbuff, err
    if RAW_MODE ~= 1 then
         rawbuff, err = zbuff.create(60 * 1024, 0, zbuff.HEAP_AUTO)
    else
        rawbuff, err = zbuff.create(640 * 480 * 2, 0, zbuff.HEAP_AUTO) -- gc032a
        -- local rawbuff = zbuff.create(240 * 320 * 2, zbuff.HEAP_AUTO)  --bf302a
    end
    if rawbuff == nil then
        log.info(err)
    end
end

function AirCam0310.start_cam()
    log.info("摄像头启动")
    air8000epmv13_cam_int()

    --spi的id和摄像头的id
    local cspiId, i2cId = 1, 1

    --配置iic
    i2c.setup(i2cId, i2c.FAST)
    gpio.setup(5, 0) -- PD拉低
    -- camera_id = bf30a2Init(cspiId,i2cId,25500000,SCAN_MODE,SCAN_MODE)
    camera_id = gc0310Init(cspiId, i2cId, 25500000, SCAN_MODE, SCAN_MODE)
    -- camera_id = gc032aInit(cspiId, i2cId, 24000000, SCAN_MODE, SCAN_MODE)
    camera.stop(camera_id)
    camera.start(camera_id)
    --打开LCD预览功能
    log.info("打开LCD预览",camera.preview(camera_id, true),camera_id)
    -- log.info("按下boot开始测试", camera_id)
    log.info(rtos.meminfo("sys"))
    log.info(rtos.meminfo("psram"))

    while(1) do
        sys.wait(100)
        if AirCam0310.isquit then
          log.info("摄像头关闭:", camera_id)
          log.info("打开LCD预览",camera.preview(camera_id, false),camera_id)
          camera.stop(camera_id)
          camera.close(camera_id)
		  sys.wait(10)
		  lcd.set_direction(0)
          break
        end
    end
end

return AirCam0310