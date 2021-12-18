--- 模块功能：video_play_demo
-- @module video_play
-- @author Dozingfiretruck
-- @release 2021.09.06

-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "video_play_demo"
VERSION = "1.0.1"

log.info("main", PROJECT, VERSION)

-- sys库是标配
_G.sys = require("sys")

--添加硬狗防止程序卡死
--wdt.init(15000)--初始化watchdog设置为15s
--sys.timerLoopStart(wdt.feed, 10000)--10s喂一次狗

sys.taskInit(function()
    sdio.init(0)
    sdio.sd_mount(0,"/sd",0)

    spi_lcd = spi.deviceSetup(0,20,0,0,8,20*1000*1000,spi.MSB,1,1)
    log.info("lcd.init",
    lcd.init("st7735s",{port = "device",pin_dc = 17, pin_pwr = 7,pin_rst = 19,direction = 2,w = 160,h = 80,xoffset = 1,yoffset = 26},spi_lcd))
    
--[[-- v0006及以后版本可用pin方式
    spi_lcd = spi.deviceSetup(0,pin.PB04,0,0,8,20*1000*1000,spi.MSB,1,1)
    log.info("lcd.init",
    lcd.init("st7735s",{port = "device",pin_dc = pin.PB01, pin_pwr = pin.PB00,pin_rst = pin.PB03,direction = 2,w = 160,h = 80,xoffset = 1,yoffset = 26},spi_lcd))
]]
    -- 使用ffmpeg.exe将视频转成字节流文件sxd.rgb放入TF卡
    local rgb_file = "sxd.rgb"
    local file_size = fs.fsize("/sd/"..rgb_file)
    print("/sd/"..rgb_file.." file_size",file_size)
    local file = io.open("/sd/"..rgb_file, "rb")
    if file then
        local file_cnt = 0
        local buff = zbuff.create(25600)--分辨率160*80 160*80*2=25600
        repeat
            if file:fill(buff) then
                file_cnt = file_cnt + 25600
                lcd.draw(0, 0, 159, 79, buff)
                sys.wait(20)
            end
        until( file_size - file_cnt < 25600 )
        local temp_data = file:fill(buff,0,file_size - file_cnt)
        lcd.draw(0, 0, 159, 79, buff)
        sys.wait(30)
        file:close()
    end
    while true do
        sys.wait(1000)
    end
end)

-- 主循环, 必须加
sys.run()
