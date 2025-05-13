
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "fatfs"
VERSION = "1.0.0"

-- sys库是标配
_G.sys = require("sys")
_G.sysplus = require("sysplus")

--[[
注意：B10开发板需要SD_3.3V和SWD3.3V短接
]]

-- 特别提醒, 由于FAT32是DOS时代的产物, 文件名超过8个字节是需要额外支持的(需要更大的ROM)
-- 例如 /sd/boottime 是合法文件名, 而/sd/boot_time就不是合法文件名, 需要启用长文件名支持.

--网络任务
-- 联网函数, 可自行删减
-- sys.taskInit(function()
--     -----------------------------
--     -- 统一联网函数, 可自行删减
--     ----------------------------
--     if wlan and wlan.connect then
--         -- wifi 联网, Air8101系列均支持
--         local ssid = "Xiaomi 15"
--         local password = "wsh123456"
--         log.info("wifi", ssid, password)
--         wlan.init()
--         wlan.connect(ssid, password, 1)
--         --等待WIFI联网结果，WIFI联网成功后，内核固件会产生一个"IP_READY"消息
--         local result, data = sys.waitUntil("IP_READY")
--         log.info("wlan", "IP_READY", result, data)
--     end
--     log.info("已联网")
--     sys.publish("net_ready")
-- end)

-- spi_id,pin_cs
local function fatfs_spi_pin()
    return 0, 3, fatfs.SDIO
end

sys.taskInit(function()
    sys.wait(1000)
    -- fatfs.debug(1) -- 若挂载失败,可以尝试打开调试信息,查找原因


    local spi_id, pin_cs,tp = fatfs_spi_pin()
    fatfs.mount(tp or fatfs.SPI, "/sd", spi_id, pin_cs, 24 * 1000 * 1000) --挂载fatfs

    local data, err = fatfs.getfree("/sd")  --获取可用空间信息
    if data then
        log.info("fatfs", "getfree", json.encode(data))
    else
        log.info("fatfs", "err", err)
    end

    -- #################################################
    -- 文件操作测试
    -- #################################################
    local f = io.open("/sd/boottime", "rb") --
    local c = 0
    if f then
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
    f = io.open("/sd/boottime", "wb")
    if f ~= nil then
        log.info("fs", "write c to file", c, tostring(c))
        f:write(tostring(c))
        f:close()
    else
        log.warn("sdio", "mount not good?!")
    end
    if fs then
        log.info("fsstat", fs.fsstat("/")) -- 打印根分区的信息
        log.info("fsstat", fs.fsstat("/sd"))  --打印sd卡文件系统分区信息
    end

    -- 测试一下追加, fix in 2021.12.21
    os.remove("/sd/test_a")
    sys.wait(50)
    f = io.open("/sd/test_a", "w")
    if f then
        f:write("ABC")
        f:close()
    end
    f = io.open("/sd/test_a", "a+")
    if f then
        f:write("def")
        f:close()
    end
    f = io.open("/sd/test_a", "r")
    if  f then
        local data = f:read("*a")
        log.info("data", data, data == "ABCdef")
        f:close()
    end

    -- 测试一下按行读取, fix in 2022-01-16
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

    -- #################################################
end)


-- 按需打印
-- code 响应值, 若大于等于 100 为服务器响应, 小于的均为错误代码
-- headers是个table, 一般作为调试数据存在
-- body是字符串. 注意lua的字符串是带长度的byte[]/char*, 是可以包含不可见字符的
-- http下载文件到sd卡功能演示任务
-- sys.taskInit(function()
--     sys.waitUntil("net_ready") -- 等联网
--     sys.wait(5000)
--     log.info("测试http下载文件到sd卡中")
--     local code, headers, body = http.request("GET", "http://airtest.openluat.com:2900/download/12345.txt", {}, "",{ dst = "/sd/test.txt" }).wait()
--     log.info("http.get", code, headers, body)
--     log.info("text size", fs.fsize("/sd/test.txt"))
-- end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
