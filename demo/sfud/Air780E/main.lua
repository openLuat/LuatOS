
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "sfuddemo"
VERSION = "1.0.0"


--[[
接线说明, 以780E开发板为例, 需要1.5版本或以上. 1.4版本SPI分布有所不同

https://wiki.luatos.com/chips/air780e/board.html

 xx脚指开发板pinout图上的顺序编号, 非GPIO编号

Flash -- 开发板
GND   -- 16脚, GND
VCC   -- 15脚, 3.3V
CLK   -- 14脚, GPIO11/SPI0_CLK, 时钟. 如果是1.4版本的开发板, 接05脚的GPIO11/UART2_TXD
MOSI  -- 13脚, GPIO09/SPI0_MOSI,主控数据输出
MISO  -- 11脚, GPIO10/SPI0_MISO,主控数据输入. 如果是1.4版本的开发板, 接05脚的GPIO10/UART2_RXD
CS    -- 10脚, GPIO08/SPI0_CS,片选.

注意: 12脚是跳过的, 接线完毕后请检查好再通电!!
]]

log.info("main", PROJECT, VERSION)

sys = require("sys")

--添加硬狗防止程序卡死
if wdt then
    wdt.init(9000)--初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000)--3s喂一次狗
end

sys.taskInit(function()
    -- log.info("sfud.init",sfud.init(0,8,20 * 1000 * 1000))--此方法spi总线无法挂载多设备
    spi_flash = spi.deviceSetup(0,8,0,0,8,25600000,spi.MSB,1,0)
    local ret = sfud.init(spi_flash)
    if ret then
        log.info("sfud.init ok")
    else
        log.info("sfud.init error", ret)
        return
    end
    log.info("sfud.getDeviceNum",sfud.getDeviceNum())
    local sfud_device = sfud.getDeviceTable()
    log.info("sfud.eraseWrite",sfud.eraseWrite(sfud_device,1024,"sfud"))
    log.info("sfud.read",sfud.read(sfud_device,1024,4))
    log.info("sfud.mount",sfud.mount(sfud_device,"/sfud/", 1024*1024, 1024*1024))
    log.info("fsstat", fs.fsstat("/sfud/"))
end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
