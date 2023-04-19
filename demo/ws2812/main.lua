-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "ws2812demo"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- 引入必要的库文件(lua编写), 内部库不需要require
sys = require("sys")

local rtos_bsp = rtos.bsp():lower()
if rtos_bsp=="air101" or rtos_bsp=="air103" then
    mcu.setClk(240)
end

if wdt then
    --添加硬狗防止程序卡死，在支持的设备上启用这个功能
    wdt.init(9000)--初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000)--3s喂一次狗
end

--可选pwm,gpio,spi方式驱动,API详情查看wiki https://wiki.luatos.com/api/sensor.html

-- mode pin/pwm_id/spi_id T0H T0L T1H T1L
local function ws2812_conf()
    local rtos_bsp = rtos.bsp()
    if rtos_bsp == "AIR101" then
        return "pin",pin.PA7,0,20,20,0      --此为pin方式直驱,注意air101主频设置240
    elseif rtos_bsp == "AIR103" then
        return "pin",pin.PA7,0,20,20,0      --此为pin方式直驱,注意air103主频设置240
    elseif rtos_bsp == "AIR105" then
        return "pin",pin.PD13,0,10,10,0     --此为pin方式直驱
    elseif rtos_bsp == "ESP32C3" then
        return "pin",2,0,10,10,0            --此为pin方式直驱
    elseif rtos_bsp == "ESP32S3" then
        return "pin",2,0,10,10,0            --此为pin方式直驱
    elseif rtos_bsp == "EC618" then
        return "spi",0            --air780e 只能通过spi方式驱动
    else
        log.info("main", "bsp not support")
        return
    end
end

local show_520 = {
    {0x0000ff,0x0000ff,0x0000ff,0x0000ff,0x0000ff,0x0000ff,0x0000ff,0x0000ff,0x0000ff,0x0000ff,0x0000ff,0x0000ff,0x0000ff,0x0000ff,0x0000ff,0x0000ff,0x0000ff,0x0000ff,0x0000ff,0x0000ff,0x0000ff,0x0000ff,0x0000ff,0x0000ff},
    {0x0000ff,0x00ff00,0x00ff00,0x0000ff,0x0000ff,0x00ff00,0x00ff00,0x0000ff,0x0000ff,0x0000ff,0x0000ff,0x0000ff,0x0000ff,0x0000ff,0x0000ff,0x0000ff,0x0000ff,0x0000ff,0x0000ff,0x0000ff,0x0000ff,0x0000ff,0x0000ff,0x0000ff},
    {0x00ff00,0x00ff00,0x00ff00,0x00ff00,0x00ff00,0x00ff00,0x00ff00,0x00ff00,0x0000ff,0x00ff00,0x00ff00,0x00ff00,0x0000ff,0x00ff00,0x00ff00,0x00ff00,0x0000ff,0x00ff00,0x00ff00,0x00ff00,0x0000ff,0x0000ff,0x0000ff,0x0000ff},
    {0x00ff00,0x00ff00,0x00ff00,0x00ff00,0x00ff00,0x00ff00,0x00ff00,0x00ff00,0x0000ff,0x00ff00,0x0000ff,0x0000ff,0x0000ff,0x0000ff,0x0000ff,0x00ff00,0x0000ff,0x00ff00,0x0000ff,0x00ff00,0x0000ff,0x0000ff,0x0000ff,0x0000ff},
    {0x00ff00,0x00ff00,0x00ff00,0x00ff00,0x00ff00,0x00ff00,0x00ff00,0x00ff00,0x0000ff,0x00ff00,0x00ff00,0x00ff00,0x0000ff,0x00ff00,0x00ff00,0x00ff00,0x0000ff,0x00ff00,0x0000ff,0x00ff00,0x0000ff,0x0000ff,0x0000ff,0x0000ff},
    {0x0000ff,0x00ff00,0x00ff00,0x00ff00,0x00ff00,0x00ff00,0x00ff00,0x0000ff,0x0000ff,0x0000ff,0x0000ff,0x00ff00,0x0000ff,0x00ff00,0x0000ff,0x0000ff,0x0000ff,0x00ff00,0x0000ff,0x00ff00,0x0000ff,0x0000ff,0x0000ff,0x0000ff},
    {0x0000ff,0x0000ff,0x00ff00,0x00ff00,0x00ff00,0x00ff00,0x0000ff,0x0000ff,0x0000ff,0x00ff00,0x00ff00,0x00ff00,0x0000ff,0x00ff00,0x00ff00,0x00ff00,0x0000ff,0x00ff00,0x00ff00,0x00ff00,0x0000ff,0x0000ff,0x0000ff,0x0000ff},
    {0x0000ff,0x0000ff,0x0000ff,0x00ff00,0x00ff00,0x0000ff,0x0000ff,0x0000ff,0x0000ff,0x0000ff,0x0000ff,0x0000ff,0x0000ff,0x0000ff,0x0000ff,0x0000ff,0x0000ff,0x0000ff,0x0000ff,0x0000ff,0x0000ff,0x0000ff,0x0000ff,0x0000ff},
}
local show_520_w = 24
local show_520_h = 8

local ws2812_w = 8
local ws2812_h = 8
local buff = zbuff.create({ws2812_w,ws2812_h,24},0x000000)

local function ws2812_roll_show(show_data,data_w)
    local m = 0
    while 1 do
        for j=0,ws2812_w-1 do
            if j%2==0 then
                for i=ws2812_w-1,0,-1 do
                    if m+ws2812_w-i>data_w then
                        buff:pixel(i,j,show_data[j+1][m+ws2812_w-i-data_w])
                    else
                        buff:pixel(i,j,show_data[j+1][m+ws2812_w-i])
                    end
                end
            else
                for i=0,ws2812_w-1 do
                    if m+i+1>data_w then
                        buff:pixel(i,j,show_data[j+1][m+i+1-data_w])
                    else
                        buff:pixel(i,j,show_data[j+1][m+i+1])
                    end
                end
            end
        end
        m = m+1
        if m==data_w then m=0 end

        --可选pwm,gpio,spi方式驱动,API详情查看wiki https://wiki.luatos.com/api/sensor.html
        local mode = ws2812_conf()
        if mode == "pin" then
            local _,pin,T0H,T0L,T1H,T1L = ws2812_conf()
            sensor.ws2812b(pin,buff,T0H,T0L,T1H,T1L)
        elseif mode == "pwm" then
            local _,pwm_id = ws2812_conf()
            sensor.ws2812b_pwm(pwm_id,buff)
        elseif mode == "spi" then
            local _,spi_id = ws2812_conf()
            sensor.ws2812b_spi(spi_id,buff)
        else
            while 1 do
                sys.wait(1000)
                log.info("main", "bsp not support yet")
            end
        end
        sys.wait(300)
    end
end
sys.taskInit(function()
    sys.wait(500)
    ws2812_roll_show(show_520,show_520_w)
end)
-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
