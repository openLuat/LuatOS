
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "lcddemo"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- sys库是标配
_G.sys = require("sys")

--[[
-- LCD接法示例
LCD管脚       Air780E管脚            
GND          GND                          
VCC          3.3V                      
SCL          (GPIO11)          
SDA          (GPIO09)         
RES          (GPIO01)       
DC           (GPIO10)       
CS           (GPIO08)       
BL(可以不接)  (GPIO22)      

提示:
1. 只使用SPI的时钟线(SCK)和数据输出线(MOSI), 其他均为GPIO脚
2. 数据输入(MISO)和片选(CS), 虽然是SPI, 但已复用为GPIO, 并非固定,是可以自由修改成其他脚
3. 若使用多个SPI设备, 那么RES/CS请选用非SPI功能脚
4. BL可以不接的
]]

--添加硬狗防止程序卡死
if wdt then
    wdt.init(9000)--初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000)--3s喂一次狗
end

local spi_id    =   0
local pin_reset =   1
local pin_dc    =   10
local pin_cs    =   8
local bl        =   22

--[[设置并启用SPI
    @param1 SPI号
    @param2 cs片选引脚
    @param3 CPHA 默认0,可选0/1
    @param4 CPOL 默认0,可选0/1
    @param5 数据宽度,默认8bit
    @param6 波特率,默认20M=20000000
    @param7 大小端, 默认spi.MSB, 可选spi.LSB
    @return spi_device 
]]
spi_lcd = spi.deviceSetup(spi_id,pin_cs,0,0,8,20*1000*1000,spi.MSB,1,0)
port = "device"

--[[ 此为合宙售卖的1.8寸TFT LCD LCD 分辨率:128X160 屏幕ic:st7735 购买地址:https://item.taobao.com/item.htm?spm=a1z10.5-c.w4002-24045920841.19.6c2275a1Pa8F9o&id=560176729178]]
--[[lcd显示屏初始化
    @param1 lcd类型
    @param2 附加参数,table
    @param3 spi设备,当port = “device”时有效
    @param4 允许初始化在lcd service里运行，默认是false
]]
lcd.init("st7735",{port = port,pin_dc = pin_dc, pin_pwr = bl, pin_rst = pin_reset,direction = 0,w = 128,h = 160,xoffset = 0,yoffset = 0},spi_lcd)

--[[ 此为合宙售卖的0.96寸TFT LCD LCD 分辨率:160X80 屏幕ic:st7735s 购买地址:https://item.taobao.com/item.htm?id=661054472686]]
--lcd.init("st7735v",{port = port,pin_dc = pin_dc, pin_pwr = bl, pin_rst = pin_reset,direction = 1,w = 160,h = 80,xoffset = 0,yoffset = 24},spi_lcd)

--如果显示颜色相反，请解开下面一行的注释，关闭反色
--lcd.invoff()
--0.96寸TFT如果显示依旧不正常，可以尝试老版本的板子的驱动
-- lcd.init("st7735s",{port = port,pin_dc = pin_dc, pin_pwr = bl, pin_rst = pin_reset,direction = 2,w = 160,h = 80,xoffset = 0,yoffset = 0},spi_lcd)

-- 不在内置驱动的, 看上一级目录的demo/lcd_custom

sys.taskInit(function()
    -- 开启缓冲区, 刷屏速度会加快, 但也消耗2倍屏幕分辨率的内存
    -- lcd.setupBuff()          -- 使用lua内存
    -- lcd.setupBuff(nil, true) -- 使用sys内存, 只需要选一种
    -- lcd.autoFlush(false)

    while 1 do 
        -- 清屏，默认背景色
        lcd.clear()
        --log.info("wiki", "https://wiki.luatos.com/api/lcd.html")
        -- API 文档 https://wiki.luatos.com/api/lcd.html
        if lcd.showImage then
            -- 注意, jpg需要是常规格式, 不能是渐进式JPG
            -- 如果无法解码, 可以用画图工具另存为,新文件就能解码了
            -- 判断要显示的图片是否存在
            log.info("文件/luadb/logo.jpg是否存在",io.exists("/luadb/logo.jpg")) 
            --[[显示图片，当前只支持jpg,jpeg
                @param1 x坐标
                @param2 y坐标
                @param3 文件路径
            ]]
            lcd.showImage(40,0,"/luadb/logo.jpg")
            sys.wait(1000)
            
        end
        --[[在两点之间画一条线
            @param1 第一个点的X位置
            @param2 第一个点的y位置
            @param3 第二个点的x位置
            @param4 第二个点的y位置
            @param5 绘画颜色,默认前景色[可选]
        ]]
        log.info("lcd.drawLine", lcd.drawLine(10,90,80,90,0x001F))
        --[[从x / y位置（左上边缘）开始绘制一个框
            @param1 左上边缘的X位置
            @param2 左上边缘的Y位置
            @param3 右下边缘的X位置
            @param4 右下边缘的Y位置
            @param5 绘画颜色,默认前景色[可选]
        ]]
        log.info("lcd.drawRectangle", lcd.drawRectangle(10,110,50,140,0xF800))
        --[[从x / y位置（圆心）开始绘制一个圆
            @param1 圆心的X位置
            @param2 圆心的Y位置
            @param3 半径
            @param4 绘画颜色,默认前景色[可选]
        ]]
        log.info("lcd.drawCircle", lcd.drawCircle(100,120,20,0x0CE0))
        sys.wait(1000)
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
