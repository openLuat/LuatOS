--[[
@module  sfud_test
@summary sfud_test测试功能模块
@version 1.0
@date    2025.07.01
@author  孟伟
@usage
本demo演示的功能为：使用Air780EHM核心板通过SFUD库实现对SPI Flash的高效操作，并可以挂载sfud lfs文件系统，通过文件系统相关接口去操作sfud lfs文件系统中的文件，并演示文件的读写、删除、追加等操作。
以 Air780EHM核心板为例, 接线如下:
Air780EHM            SPI_FLASH
GND(任意)            GND
VDD_EXT              VCC
GPIO8/SPI0_CS        CS,片选
SPI0_SLK             CLK,时钟
SPI0_MOSI            DI,主机输出,从机输入
SPI0_MISO            DO,主机输入,从机输出
]]
--使用SPI0，CS接在gpio8上
local spi_id,pin_cs = 0,8

function sfud_test_func()
    sys.wait(1000)
    log.info("sfud", "SPI", spi_id, "CS PIN", pin_cs)
    --以对象的方式初始化spi_flash
    spi_flash = spi.deviceSetup(spi_id,pin_cs,0,0,8,20*1000*1000,spi.MSB,1,0)
    log.info("sfud", "spi_flash", spi_flash)
    --初始化sfud，并判断初始化结果
    local ret = sfud.init(spi_flash)
    if ret then
        log.info("sfud.init ok")
    else
        log.info("sfud.init Error")
        return
    end
    --获取flash设备信息表中的设备总数
    log.info("sfud.getDeviceNum",sfud.getDeviceNum())
    --获取flash设备信息表
    local sfud_device = sfud.getDeviceTable()
    --判断是否支持sfud.getInfo接口，支持的话获取 Flash 容量和page大小
    if sfud.getInfo then
        log.info("sfud.getInfo", sfud.getInfo(sfud_device))
    end
    --定义两个变量，用来控制是通过sfud接口来操作flash还是挂载为sfud lfs文件系统。也可以同时使用两种方式，不过要注意同时使用时flash地址和挂载时的偏移量需要设计好
    local test_sfud_raw = true
    local test_sfud_mount = false
    --通过sfud接口对flash进行写入和读取操作
    if test_sfud_raw then
        local test_str = "luatos-sfud1234567890123456789012345678901234567890"
        log.info("sfud.eraseWrite",sfud.eraseWrite(sfud_device,1024,test_str))
        local read_str = sfud.read(sfud_device,1024,#test_str)
        if test_str == read_str then
            log.info("sfud 写入与读取数据成功")
        else
            log.info("sfud 写入与读取数据失败")
        end

    end
    --挂载为sfud lfs文件系统，通过文件系统相关接口去操作sfud lfs文件系统中的文件，并演示文件的读写、删除、追加等操作。
    if test_sfud_mount then
        --挂载sfud lfs文件系统
        local ret = sfud.mount(sfud_device,"/sfud")
        log.info("sfud.mount", ret)
        if ret then
            log.info("sfud", "挂载成功")
            log.info("fsstat", fs.fsstat("/sfud"))

            -- 挂载成功后，可以像操作文件一样操作
            local f = io.open("/sfud/test", "w")
            local write_str = os.date()
            log.info("/sfud/test文件写入数据",write_str)
            --写入当前时间到文件中
            f:write(write_str)
            --关闭文件
            f:close()
            --读取文件内容并打印
            local read_str = io.readFile("/sfud/test")
            log.info("sfud_lfs read", read_str)
            if read_str == write_str then
                log.info("写入测试成功，写入字符串与读出字符串一样")
            else
                log.info("写入测试失败，写入字符串与读出字符串不一样")
            end
            -- 文件追加
            --文件追加测试写入之前先删除一下
            os.remove("/sfud/test2")
            --将"LuatOS"字符串写入到test2文件中
            io.writeFile("/sfud/test2", "LuatOS-")
            --以追加的方式打开test2文件
            local f = io.open("/sfud/test2", "a+")
            local time_str = os.date()
            f:write(time_str)
            write_str = "LuatOS-"..time_str
            log.info("/sfud/test2",write_str)
            --关闭文件
            f:close()
            read_str = io.readFile("/sfud/test2")
            log.info("sfud read", read_str)
            if write_str == read_str then
                log.info("追加测试成功，写入字符串与读出字符串一样")
            else
                log.info("追加测试失败，写入字符串与读出字符串不一样")
            end
        else
            log.info("sfud", "挂载失败")
        end


    end
end
--创建并且启动一个task
--运行这个task的主函数sfud_test_func
sys.taskInit(sfud_test_func)