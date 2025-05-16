--- 模块功能：lcddemo
-- @module lvgl
-- @author Dozingfiretruck
-- @release 2025.03.13

-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "lvgldemo"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- sys库是标配
_G.sys = require("sys")

-- UI带屏的项目一般不需要低功耗了吧, Air101/Air103设置到最高性能
if mcu and (rtos.bsp() == "AIR101" or rtos.bsp() == "AIR103" or rtos.bsp() == "AIR601" ) then
    mcu.setClk(240)
end

--[[
-- LCD接法示例
LCD管脚       Air780E管脚    Air101/Air103管脚   Air105管脚         
GND          GND            GND                 GND                 
VCC          3.3V           3.3V                3.3V                
SCL          (GPIO11)       (PB02/SPI0_SCK)     (PC15/HSPI_SCK)     
SDA          (GPIO09)       (PB05/SPI0_MOSI)    (PC13/HSPI_MOSI)    
RES          (GPIO01)       (PB03/GPIO19)       (PC12/HSPI_MISO)    
DC           (GPIO10)       (PB01/GPIO17)       (PE08)              
CS           (GPIO08)       (PB04/GPIO20)       (PC14/HSPI_CS)      
BL(可以不接)  (GPIO22)       (PB00/GPIO16)       (PE09)              


提示:
1. 只使用SPI的时钟线(SCK)和数据输出线(MOSI), 其他均为GPIO脚
2. 数据输入(MISO)和片选(CS), 虽然是SPI, 但已复用为GPIO, 并非固定,是可以自由修改成其他脚
3. 若使用多个SPI设备, 那么RES/CS请选用非SPI功能脚
4. BL可以不接的, 若使用Air10x屏幕扩展板,对准排针插上即可
]]

--添加硬狗防止程序卡死
if wdt then
    wdt.init(9000)--初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000)--3s喂一次狗
end

local lcd_use_buff = false  -- 是否使用缓冲模式, 提升绘图效率，占用更大内存


local rtos_bsp = rtos.bsp()
local chip_type = hmeta.chip()
-- 根据不同的BSP返回不同的值
-- spi_id,pin_reset,pin_dc,pin_cs,bl
function lcd_pin()
    if rtos_bsp == "AIR101" then
        return 0,pin.PB03,pin.PB01,pin.PB04,pin.PB00
    elseif rtos_bsp == "AIR103" then
        return 0,pin.PB03,pin.PB01,pin.PB04,pin.PB00
    elseif rtos_bsp == "AIR105" then
        return 5,pin.PC12,pin.PE08,pin.PC14,pin.PE09
    elseif rtos_bsp == "ESP32C3" then
        return 2,10,6,7,11
    elseif rtos_bsp == "ESP32S3" then
        return 2,16,15,14,13
    elseif rtos_bsp == "EC618" then
        return 0,1,10,8,22
    elseif string.find(rtos_bsp,"EC718") or string.find(chip_type,"EC718") then
        return lcd.HWID_0,36,0xff,0xff,25 -- 注意:EC718P有硬件lcd驱动接口, 无需使用spi,当然spi驱动也支持
    elseif string.find(rtos_bsp,"Air8101") then
        lcd_use_buff = true -- RGB仅支持buff缓冲模式
        return lcd.RGB,36,0xff,0xff,25
    else
        log.info("main", "bsp not support")
        return
    end
end

local spi_id,pin_reset,pin_dc,pin_cs,bl = lcd_pin() 

if spi_id ~= lcd.HWID_0 and spi_id ~= lcd.RGB then
    spi_lcd = spi.deviceSetup(spi_id,pin_cs,0,0,8,20*1000*1000,spi.MSB,1,0)
    port = "device"
else
    port = spi_id
end

if spi_id == lcd.RGB then
    lcd.init("h050iwv",
            {port = port,pin_dc = pin_dc, pin_pwr = bl, pin_rst = pin_reset,
            direction = 0,w = 800,h = 480,xoffset = 0,yoffset = 0})
    
    -- lcd.init("hx8282",
    --         {port = port,pin_pwr = bl, pin_rst = pin_reset,
    --         direction = 0,w = 1024,h = 600,xoffset = 0,yoffset = 0})

    -- lcd.init("nv3052c",
    --         {port = port,pin_pwr = bl, pin_rst = pin_reset,
    --         direction = 0,w = 720,h = 1280,xoffset = 0,yoffset = 0})

    -- lcd.init("st7701sn",
    --         {port = port,pin_pwr = bl, pin_rst = pin_reset,
    --         direction = 0,w = 480,h = 854,xoffset = 0,yoffset = 0})

    -- lcd.init("st7701s",
    --         {port = port,pin_pwr = bl, pin_rst = pin_reset,
    --         direction = 0,w = 480,h = 480,xoffset = 0,yoffset = 0})

    -- lcd.init("custom",
    --         {port = port,hbp = 46, hspw = 2, hfp = 48,vbp = 24, vspw = 2, vfp = 24,
    --         bus_speed = 60*1000*1000,
    --         direction = 0,w = 800,h = 480,xoffset = 0,yoffset = 0})

    -- "jd9261t"
    -- lcd.init("custom",{port = port,
    --         hbp = 180, hspw = 2, hfp = 48,vbp =24, vspw = 2, vfp = 158,
    --         bus_speed = 60*1000*1000,direction = 0,w =720,h = 720})

else
    --[[ 此为合宙售卖的1.8寸TFT LCD LCD 分辨率:128X160 屏幕ic:st7735 购买地址:https://item.taobao.com/item.htm?spm=a1z10.5-c.w4002-24045920841.19.6c2275a1Pa8F9o&id=560176729178]]
    lcd.init("st7735",{port = port,pin_dc = pin_dc, pin_pwr = bl, pin_rst = pin_reset,direction = 0,w = 128,h = 160,xoffset = 0,yoffset = 0},spi_lcd)
    
    -- [[ 此为合宙售卖的0.96寸TFT LCD LCD 分辨率:160X80 屏幕ic:st7735s 购买地址:https://item.taobao.com/item.htm?id=661054472686]]
    -- lcd.init("st7735v",{port = port,pin_dc = pin_dc, pin_pwr = bl, pin_rst = pin_reset,direction = 1,w = 160,h = 80,xoffset = 0,yoffset = 24},spi_lcd)
    
    -- [[ 此为合宙售卖的ec718系列专用硬件双data驱动TFT LCD LCD 分辨率:320x480 屏幕ic:nv3037 购买地址:https://item.taobao.com/item.htm?id=764253232987&skuId=5258482696347&spm=a1z10.1-c-s.w4004-24087038454.8.64961170w5EdoA]]
    -- lcd.init("nv3037",{port = port,pin_dc = pin_dc, pin_pwr = bl, pin_rst = pin_reset,direction = 0,w = 320,h = 480,xoffset = 0,yoffset = 0,interface_mode=lcd.DATA_2_LANE},spi_lcd)
    
    -- lcd.init("st7789",{port = port,pin_dc = pin_dc, pin_pwr = bl, pin_rst = pin_reset,direction = 0,w = 240,h = 320,xoffset = 0,yoffset = 0},spi_lcd)
	-- [[ QSPI接口无RAM屏幕，必须开启lcd_use_buff ]]
	-- lcd.init("jd9261t_inited",{port = port,pin_dc = pin_dc, pin_pwr = bl, pin_rst = pin_reset,direction = 0,w = 480,h = 480,xoffset = 0,yoffset = 0,interface_mode=lcd.QSPI_MODE,bus_speed=60000000,flush_rate=658,vbp=19,vfp=108,vs=2},spi_lcd)
	-- lcd_use_buff = true
end

--如果显示颜色相反，请解开下面一行的注释，关闭反色
--lcd.invoff()

-- 不在内置驱动的, 看demo/lcd_custom

local img_luatos, slider_value

local function event_handler(obj, event)
    if (event == lvgl.EVENT_VALUE_CHANGED) then
        local LV_VER_RES = lvgl.disp_get_ver_res()
        local value = lvgl.slider_get_value(obj)
        lvgl.label_set_text(slider_value, value)
        lvgl.obj_set_x(img_luatos, LV_VER_RES*value/100)
    end
end

sys.taskInit(function()
    -- 开启缓冲区, 刷屏速度回加快, 但也消耗2倍屏幕分辨率的内存
    if lcd_use_buff then
        lcd.setupBuff(nil, true) -- 使用sys内存, 只需要选一种
        -- lcd.setupBuff()       -- 使用lua内存, 只需要选一种
        lcd.autoFlush(false)
    end
    -- sys.wait(5000)
    log.info("lvgl", lvgl.init())

    if tp then
        softI2C = i2c.createSoft(8, 5)
        tp_device =  tp.init("gt911",{port=softI2C,pin_rst = 9,pin_int = 6})
        
        lvgl.indev_drv_register("pointer", "touch", tp_device)
    end

    local scr = lvgl.obj_create(nil, nil)

    local lv_slider = lvgl.slider_create(scr, nil)
    lvgl.obj_align(lv_slider, lvgl.scr_act(), lvgl.ALIGN_CENTER, 0, 0)
    lvgl.obj_set_event_cb(lv_slider, event_handler)

    img_luatos = lvgl.img_create(scr)
    lvgl.img_set_src(img_luatos, "/luadb/logo.jpg")
    lvgl.obj_set_y(img_luatos,lvgl.obj_get_y(lv_slider) - 100)

    slider_value = lvgl.label_create(scr)
    lvgl.label_set_text(slider_value, 0)
    lvgl.obj_align(slider_value, lv_slider, lvgl.ALIGN_OUT_BOTTOM_MID, 0, 20)

    lvgl.scr_load(scr)
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
