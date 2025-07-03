--[[
@module  tf_test
@summary tf_test测试功能模块
@version 1.0
@date    2025.07.02
@author  李源龙
@usage
使用Air780EHM核心板通过fatfs库和io库实现对tf卡的高效操作，并可以挂载fatfs文件系统，通过文件系统相关接口去操作fatfs文件系统中的文件，并演示文件的读写、删除、追加以及HTTP服务器下载到SD卡等操作。
以 Air780EHM核心板为例,和AirMICROSD_1000接线如下:
Air780EHM            AirMICROSD_1000
GND(任意)            GND
VDD_EXT              VCC
GPIO8/SPI0_CS        CS,片选
SPI0_SLK             CLK,时钟
SPI0_MOSI            MOSI,主机输出,从机输入
SPI0_MISO            MISO,主机输入,从机输出
]]


local function main_task()
    sys.wait(1000)
    -- fatfs.debug(1) -- 若挂载失败,可以尝试打开调试信息,查找原因

    -- 此为spi方式挂载SD卡
    local spi_id, pin_cs,tp = 0,8 
    spi.setup(spi_id, nil, 0, 0, pin_cs, 400 * 1000)
    gpio.setup(pin_cs, 1)
    fatfs.mount(fatfs.SPI, "/sd", spi_id, pin_cs, 24 * 1000 * 1000)

    --获取SD卡的可用空间信息
    local data, err = fatfs.getfree("/sd")
    if data then
        log.info("fatfs", "getfree", json.encode(data))
    else
        log.info("fatfs", "err", err)
    end

    -- #################################################
    -- 文件操作测试
    -- #################################################
    --只读模式，打开文件
    local f = io.open("/sd/boottime", "rb")
    local c = 0
    if f then
        --读取文件内容"a": 从当前位置开始读取整个文件。 如果已在文件末尾，返回空串。
        local data = f:read("*a")   
        log.info("fs", "data", data, data:toHex())
        c = tonumber(data)
        f:close()
    end
    log.info("fs", "boot count", c)
    if c == nil then
        c = 0
    end
    c = c + 1
    --写入模式，打开文件
    f = io.open("/sd/boottime", "wb")
    if f ~= nil then
        log.info("fs", "write c to file", c, tostring(c))
        f:write(tostring(c))
        f:close()
    else
        log.warn("sdio", "mount not good?!")
    end
    --获取文件系统信息
    if fs then
        log.info("fsstat", fs.fsstat("/"))
        log.info("fsstat", fs.fsstat("/sd"))
    end

    -- 测试一下追加
    os.remove("/sd/test_a")
    sys.wait(50)
    --打开文件，写入模式，写入内容
    f = io.open("/sd/test_a", "w")
    if f then
        f:write("ABC")
        f:close()
    end
    --打开文件，追加模式，写入内容
    f = io.open("/sd/test_a", "a+")
    if f then
        f:write("def")
        f:close()
    end
    --打开文件，只读模式
    f = io.open("/sd/test_a", "r")
    --对比下数据是不是和写入的一样
    if  f then
        local data = f:read("*a")
        log.info("data", data, data == "ABCdef")
        f:close()
    end

    -- 测试一下按行读取
    f = io.open("/sd/testline", "w")
    if f then
        f:write("abc\n")
        f:write("123\n")
        f:write("wendal\n")
        f:close()
    end
    sys.wait(100)
    f = io.open("/sd/testline", "r")
    if f then
        log.info("sdio", "line1", f:read("*l"))
        log.info("sdio", "line2", f:read("*l"))
        log.info("sdio", "line3", f:read("*l"))
        f:close()
    end

    -- 测试一下http下载到sd卡里面
    local code, headers, body =
        http.request("GET", "http://airtest.openluat.com:2900/download/1.mp3", nil, nil, {dst = "/sd/1.mp3"}).wait()
    --存到sd卡里面
    log.info("下载完成", code, headers, body)
    log.info("io.fileSize",io.fileSize("/sd/1.mp3"))
end

sys.taskInit(main_task)