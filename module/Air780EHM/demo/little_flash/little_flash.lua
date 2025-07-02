
--[[
@module  little_flash
@summary little_flash测试功能模块
@version 1.0
@date    2025.07.01
@author  孟伟
@usage
本demo是 Air780EHM + spi_flash. 以 Air780EHM核心板为例, 接线如下:

Air780EHM            SPI_FLASH
GND(任意)            GND
VDD_EXT              VCC
GPIO8/SPI0_CS        CS,片选
SPI0_SLK             CLK,时钟
SPI0_MOSI            DI,主机输出,从机输入
SPI0_MISO            DO,主机输入,从机输出
]]
--使用spi0，cs接在gpio8上
local spi_id,pin_cs = 0,8
function little_flash_func()
    sys.wait(1000)
    log.info("lf", "SPI", spi_id, "CS PIN", pin_cs)
    --以对象的方式初始化spi_flash
    spi_flash = spi.deviceSetup(spi_id,pin_cs,0,0,8,20*1000*1000,spi.MSB,1,0)
    log.info("lf", "spi_flash", spi_flash)
    little_flash_device = lf.init(spi_flash)   --初始化 little_flash
    if little_flash_device then
        log.info("lf.init ok",little_flash_device)
    else
        log.info("lf.init Error")
        return
    end

    if lf.mount then
        --挂载 little_flash lfs文件系统
        local ret = lf.mount(little_flash_device,"/little_flash")
        log.info("lf.mount", ret)
        if ret then
            log.info("little_flash", "挂载成功")
            --获取lfs文件系统信息
            log.info("fsstat", fs.fsstat("/little_flash"))

            -- 挂载成功后，可以像操作文件一样操作
            --以写模式打开文件，并返回文件句柄，io接口含义可参考lua5.3手册https://wiki.luatos.com/_static/lua53doc/contents.html
            local f = io.open("/little_flash/test", "w")
            local write_str = os.date()
            log.info("/little_flash/test文件写入数据",write_str)
            --写入当前时间到文件中
            f:write(write_str)
            --关闭文件
            f:close()
            --读取文件内容并打印
            local read_str = io.readFile("/little_flash/test")
            log.info("little_flash", read_str)
            if write_str == read_str then
                log.info("写入测试成功，写入字符串与读出字符串一样")
            else
                log.info("写入测试失败，写入字符串与读出字符串不一样")
            end

            -- 文件追加
            --文件追加测试写入之前先删除一下
            os.remove("/little_flash/test2")
            --将"LuatOS"字符串写入到test2文件中
            io.writeFile("/little_flash/test2", "LuatOS-")
            --以追加的方式打开test2文件
            local f = io.open("/little_flash/test2", "a+")
            local time_str = os.date()
            f:write(time_str)
            write_str = "LuatOS-"..time_str
            log.info("/little_flash/test2文件写入数据",write_str)

            --关闭文件
            f:close()
            read_str = io.readFile("/little_flash/test2")
            log.info("little_flash", read_str)
            if write_str == read_str then
                log.info("追加测试成功，写入字符串与读出字符串一样")
            else
                log.info("追加测试失败，写入字符串与读出字符串不一样")
            end
        else
            log.info("little_flash", "挂载失败")
        end
    end
end
--创建并且启动一个task
--运行这个task的主函数little_flash_func
sys.taskInit(little_flash_func)
