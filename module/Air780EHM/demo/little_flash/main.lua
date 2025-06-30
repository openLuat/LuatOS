
--[[
必须定义PROJECT和VERSION变量，Luatools工具会用到这两个变量，远程升级功能也会用到这两个变量
PROJECT：项目名，ascii string类型
        可以随便定义，只要不使用,就行
VERSION：项目版本号，ascii string类型
        如果使用合宙iot.openluat.com进行远程升级，必须按照"XXX.YYY.ZZZ"三段格式定义：
            X、Y、Z各表示1位数字，三个X表示的数字可以相同，也可以不同，同理三个Y和三个Z表示的数字也是可以相同，可以不同
            因为历史原因，YYY这三位数字必须存在，但是没有任何用处，可以一直写为000
        如果不使用合宙iot.openluat.com进行远程升级，根据自己项目的需求，自定义格式即可

本demo演示的功能为：
实现使用Air780EHM核心板将spi_flash挂测成lfs文件系统，并演示lfs文件系统中的文件的读写、删除、追加等操作。
]]
PROJECT = "little_flash_demo"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)


--添加硬狗防止程序卡死
if wdt then
    wdt.init(9000)--初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000)--3s喂一次狗
end
--[[
本demo是 Air780EHM + spi_flash. 以 Air780EHM核心板为例, 接线如下:

Air780EHM            SPI_FLASH
GND(任意)            GND
VDD_EXT              VCC
GPIO8/SPI0_CS        CS,片选
SPI0_SLK             CLK,时钟
SPI0_MOSI            DI,主机输出,从机输入
SPI0_MISO            DO,主机输入,从机输出
]]
local spi_id,pin_cs = 0,8
sys.taskInit(function()
    -- log.info("等5秒")
    sys.wait(1000)

    log.info("lf", "SPI", spi_id, "CS PIN", pin_cs)
    spi_flash = spi.deviceSetup(spi_id,pin_cs,0,0,8,20*1000*1000,spi.MSB,1,0) --以对象的方式初始化spi_flash
    log.info("lf", "spi_flash", spi_flash)
    little_flash_device = lf.init(spi_flash)   --初始化 little_flash
    if little_flash_device then
        log.info("lf.init ok",little_flash_device)
    else
        log.info("lf.init Error")
        return
    end

    if lf.mount then
        local ret = lf.mount(little_flash_device,"/little_flash")  --挂载 little_flash lfs文件系统
        log.info("lf.mount", ret)
        if ret then
            log.info("little_flash", "挂载成功")
            log.info("fsstat", fs.fsstat("/little_flash"))   --获取lfs文件系统信息

            -- 挂载成功后，可以像操作文件一样操作
            local f = io.open("/little_flash/test", "w")
            f:write(os.date())
            f:close()

            log.info("little_flash", io.readFile("/little_flash/test"))

            -- 文件追加
            os.remove("/little_flash/test2")
            io.writeFile("/little_flash/test2", "LuatOS")
            local f = io.open("/little_flash/test2", "a+")
            f:write(" - " .. os.date())
            f:close()

            log.info("little_flash", io.readFile("/little_flash/test2"))
        else
            log.info("little_flash", "挂载失败")
        end
    end
end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
