--[[
@module  rtc_app
@summary rtc时钟驱动模块
@version 1.0
@date    2025.10.28
@author  王城钧
@usage
本文件为rtc时钟驱动模块，核心业务逻辑为：
1、初始化RTC时钟，设置RTC时钟日期和时间，时区以及基准年；
2、获取RTC时钟时间；
3、每秒打印RTC时钟时间；

本文件没有对外接口，直接在其他功能模块中require "rtc_app"就可以加载运行；
]]

--[[
-- 本地时间是指：当前时区的时间，默认是东八区北京时间，可以通过rtc.timezone接口查询或者设置时区
-- UTC/RTC时间是指：0时区的时间
-- 东八区的时间是在UTC时间的基础上增加8个小时
-- 本文件中的两段代码演示的是东八区和RTC时间的区别
]]

local exnetif = require "exnetif"

-- RTC时钟演示(测试环境为无网络环境)
local function rtc_task1()
    rtc.setBaseYear(1900) -- 设置基准年为1900年
    local result = rtc.timezone(32) -- 设置时区为东八区
    log.info("rtc.timezone()", result) -- 打印时区信息
    -- rtc.set({ year = 2025, mon = 10, day = 28, hour = 8, min = 10, sec = 53 }) -- 设置日期和时间
    rtc.set(1761639053) -- 设置时间戳(与上一行的设置效果相同，二选一即可)
    local t1 = rtc.get()
    log.info("rtc初始时间", json.encode(t1)) -- 打印当前日期和时间
    log.info("rtc设置后的本地时间", os.date()) -- 打印当前日期和时间
    while 1 do
        log.info("os.date()", os.date()) -- 打印RTC时钟时间
        local t = rtc.get() -- 获取rtc时间
        log.info("循环rtc时间", json.encode(t)) -- 打印当前rtc时间
        sys.wait(1000) -- 等待1s，然后再次获取rtc时间和实时时间
    end
end

-- 获取基站和 NTP授时成功后的rtc时间
local function rtc_task2()
    rtc.setBaseYear(1900)              -- 设置基准年为1900年
    local result = rtc.timezone(32)    -- 设置时区为东八区
    log.info("rtc.timezone()", result) -- 打印时区信息
    exnetif.set_priority_order({
        {
            WIFI = {
                ssid = "茶室-降功耗,找合宙!", -- ssid为要连接的WiFi路由器名称，根据实际情况填写；
                password = "Air123456" -- password为要连接的WiFi路由器密码，根据实际情况填写；
            }
        }
    })
    -- rtc.set({ year = 2025, mon = 10, day = 28, hour = 19, min = 10, sec = 53 }) -- 设置日期和时间
    rtc.set(1761678653) -- 设置时间戳(与上一行的设置效果相同，二选一即可)
    log.info("rtc设置后时间", os.date()) -- 打印当前日期和时间
    while not socket.adapter(socket.dft()) do
        log.warn("sntp_task_func", "wait IP_READY", socket.dft())
        -- 在此处阻塞等待默认网卡连接成功的消息"IP_READY"
        -- 或者等待1秒超时退出阻塞等待状态;
        -- 注意：此处的1000毫秒超时不要修改的更长；
        -- 因为当使用exnetif.set_priority_order配置多个网卡连接外网的优先级时，会隐式的修改默认使用的网卡
        -- 当exnetif.set_priority_order的调用时序和此处的socket.adapter(socket.dft())判断时序有可能不匹配
        -- 此处的1秒，能够保证，即使时序不匹配，也能1秒钟退出阻塞状态，再去判断socket.adapter(socket.dft())
        sys.waitUntil("IP_READY", 1000)
    end
    socket.sntp()
    sys.waitUntil("NTP_UPDATE", 5000)
    while 1 do
        log.info("os.date()", os.date()) -- 打印实时时间
        local t = rtc.get()              -- 获取rtc时间
        log.info("循环rtc时间", json.encode(t))
        -- 打印当前rtc时间,当收到基站和 NTP授时的时候,rtc时间会自动更新为当前UTC时间(零时区)，于北京时间(东八区)相差8小时
        sys.wait(1000) -- 等待1s,然后再次获取rtc时间和实时时间
    end
end

-- 注意：以下两个任务每次测试时只能选择其一进行测试

-- 无网络情况下的rtc时间演示
sys.taskInit(rtc_task1)

-- 获取基站和 NTP授时成功后的rtc时间
-- sys.taskInit(rtc_task2)
