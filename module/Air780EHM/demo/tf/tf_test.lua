--[[]
运行环境：Air780EHM核心板+SD卡扩展板
最后修改时间：2025-7-2
使用了如下IO口：
SD卡的使用IO口：
[83, "SPI0CS", " PIN83脚, 用于SD卡片选脚"],
[84, "SPI0MISO," PIN84脚, 用于SD卡数据脚"],
[85, "SPI0MOSI", " PIN85脚, 用于SD卡数据脚"],
[86, "SPI0CLK", " PIN86脚, 用于SD卡时钟脚"],
[24, "VDD_EXT", " PIN24脚, 用于给SD卡供电脚"],
GND
执行逻辑为：
1. 初始化SD卡
2. 挂载文件系统
3. 在文件系统中创建一个文件
4. 向文件中写入数据
5. 读取文件中的数据
6. 删除文件
7. 卸载文件系统
8. 关闭SD卡

扩展了HTTP从服务器下载文件到SD卡的功能，可以下载指定URL的文件到SD卡中，并保存到SD卡里面
]]
-- sys库是标配
_G.sys = require("sys")


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