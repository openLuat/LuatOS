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
--wdt.init(9000)--初始化watchdog设置为9s
--sys.timerLoopStart(wdt.feed, 3000)--3s喂一次狗

sys.taskInit(function()
    sdio.init(0)
    sdio.sd_mount(0,"/sd",0)

    spi_lcd = spi.deviceSetup(0,pin.PB04,0,0,8,20*1000*1000,spi.MSB,1,1)
    lcd.init("st7735s",{port = "device",pin_dc = pin.PB01, pin_pwr = pin.PB00, pin_rst = pin.PB03,direction = 2,w = 160,h = 80,xoffset = 1,yoffset = 26},spi_lcd)

    -- 使用ffmpeg.exe将视频转成字节流文件sxd.rgb放入TF卡
    -- 先缩放成目标大小
    -- ffmpeg -i sxd.mp4 -vf scale=160:80 sxd.avi
    -- 然后转rbg565ble 字节流
    -- ffmpeg -i sxd.avi -pix_fmt rgb565be -vcodec rawvideo sxd.rgb

    -- 使用ffmpeg.exe将视频转成字节流文件.rgb放入TF卡 教程见 https://wiki.luatos.com/appDevelopment/video_play/105/video_play.html
    local video_w = 160
    local video_h = 80
    local rgb_file = "mwsy.rgb"

    local buff_size = video_w*video_h*2
    local file_size = fs.fsize("/sd/"..rgb_file)
    print("/sd/"..rgb_file.." file_size",file_size)
    
    local file = io.open("/sd/"..rgb_file, "rb")
    if file then
        local file_cnt = 0
        local buff = zbuff.create(buff_size)
        repeat
            if file:fill(buff) then
                file_cnt = file_cnt + buff_size
                lcd.draw(0, 0, video_w-1, video_h-1, buff)
                sys.wait(20)
            end
        until( file_size - file_cnt < buff_size )
        local temp_data = file:fill(buff,0,file_size - file_cnt)
        lcd.draw(0, 0, video_w-1, video_h-1, buff)
        sys.wait(30)
        file:close()
    end
    while true do
        sys.wait(1000)
    end
end)

-- 主循环, 必须加
sys.run()
