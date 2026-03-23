--[[
@module  netdrv_4g
@summary "通过airlink连接Air780EPM实现4G联网"驱动模块(Air1601版本)
@version 1.0
@date    2026.03.18
@author  LuatOS
@usage
本文件为"通过airlink连接Air780EPM实现4G联网"驱动模块，核心业务逻辑为：
1、初始化airlink，配置UART接口与Air780EPM通信；
2、启动airlink桥接模式；
3、配置虚拟网卡参数；
4、airlink连接状态发生变化时，在日志中进行打印；
5、设置NTP时间同步；
6、与Air780EPM进行数据交互；
7、测试网络连接情况。

本文件没有对外接口，直接在其他功能模块中require "netdrv_4G"就可以加载运行；
]]

local exnetif = require "exnetif"

local uartid = 3

-- 初始化网络，使得Air1601可以外挂Air780EPM实现4G联网功能。
local function init_airlink_net()
    uart.setup(uartid, 6000000, 8, 1)

    airlink.init()
    airlink.config(airlink.CONF_UART_ID, uartid)
    airlink.start(airlink.MODE_UART)
    netdrv.setup(socket.LWIP_USER0, netdrv.WHALE)
    netdrv.ipv4(socket.LWIP_USER0, "192.168.111.1", "255.255.255.0", "192.168.111.2")
    log.info("桥接网络设备", netdrv.link(socket.LWIP_USER0))
    
    -- 1601启动后，请求780EPM发送二维码信息
    sys.taskInit(function()
        -- 等待airlink就绪
        local retry_count = 0
        while retry_count < 30 do
            if airlink and airlink.ready() then
                log.info("netdrv_4g", "airlink就绪，请求780EPM发送二维码信息")
                airlink.sdata("REQUEST_QRINFO")
                break
            else
                log.info("netdrv_4g", "airlink未就绪，等待...")
                sys.wait(100)
                retry_count = retry_count + 1
            end
        end
    end)
end

-- 打印时间信息的工具函数
local function print_time_details()
    -- 获取本地时间字符串
    log.info("time", "本地时间字符串", os.date())
    -- 格式化本地时间字符串
    log.info("time", "格式化本地时间字符串", os.date("%Y-%m-%d %H:%M:%S"))
    -- 本地时间戳（秒级）
    log.info("time", "本地时间戳", os.time())
end

-- 时间同步主逻辑（通过HTTP请求获取时间）
local function time_sync_loop()
    log.info("time", "时间同步任务启动")
    while true do
        -- 等待网络就绪
        log.info("time", "检查网络状态...")
        while not socket.adapter(socket.LWIP_USER0) do
            log.warn("time", "等待网络就绪...")
            sys.waitUntil("IP_READY", 1000)
        end

        log.info("time", "网络就绪，开始同步时间")
        -- 通过HTTP请求获取网络时间
        local code, headers, body = http.request("GET", "https://httpbin.air32.cn/get", nil, nil, {
            timeout = 9000,
            adapter = socket.LWIP_USER0
        }).wait()

        log.info("time", "HTTP响应码", code, "响应体长度", body and #body)
        if code == 200 and body then
            log.info("time", "HTTP请求成功，获取时间信息")
            log.info("time", "响应体内容", body)
            -- 解析JSON响应中的时间
            local time_str = body:match('"time":"([^"]+)"')
            if time_str then
                log.info("time", "网络时间字符串", time_str)
                -- 解析时间字符串，格式如 "Wed, 18 Mar 2026 13:53:24 GMT"
                local pattern = "(%a+), (%d+) (%a+) (%d+) (%d+):(%d+):(%d+) GMT"
                local day, date, month, year, hour, min, sec = time_str:match(pattern)
                log.info("time", "解析结果", day, date, month, year, hour, min, sec)
                
                if day and date and month and year and hour and min and sec then
                    -- 月份映射
                    local months = {
                        Jan = 1, Feb = 2, Mar = 3, Apr = 4, May = 5, Jun = 6,
                        Jul = 7, Aug = 8, Sep = 9, Oct = 10, Nov = 11, Dec = 12
                    }
                    local month_num = months[month]
                    log.info("time", "月份转换", month, "->", month_num)
                    
                    if month_num then
                        -- 记录时间信息
                        log.info("time", "收到时间信息", year, month_num, date, hour, min, sec)
                        -- 注意：Air1601可能不支持rtos.set_time函数
                        if rtos.set_time then
                            local success = rtos.set_time(tonumber(year), tonumber(month_num), tonumber(date), 
                                                         tonumber(hour), tonumber(min), tonumber(sec))
                            log.info("time", "rtos.set_time返回值", success)
                            if success then
                                log.info("time", "时间同步成功", year, month_num, date, hour, min, sec)
                                print_time_details()
                            else
                                log.error("time", "时间同步失败")
                            end
                        else
                            log.warn("time", "Air1601不支持rtos.set_time函数，无法设置系统时间")
                        end
                    else
                        log.error("time", "无法识别月份", month)
                    end
                else
                    log.error("time", "时间字符串解析失败")
                end
            else
                log.warn("time", "无法解析时间字符串")
            end
            -- 等待1小时再次发起下次时间同步
            sys.wait(3600*1000)
        else
            log.warn("time", "时间同步失败", "code", code)
            -- 等待10秒重新发起时间同步
            sys.wait(10*1000)
        end
    end
end

-- IP就绪回调函数
local function ip_ready_func(ip, adapter)
    if adapter == socket.LWIP_USER0 then
        socket.setDNS(adapter, 1, "223.5.5.5")
        socket.setDNS(adapter, 2, "114.114.114.114")

        log.info("netdrv_4G.ip_ready_func", "IP_READY", socket.localIP(socket.LWIP_USER0))
    end
end

-- IP丢失回调函数
local function ip_lose_func(adapter)
    if adapter == socket.LWIP_USER0 then
        log.warn("netdrv_4G.ip_lose_func", "IP_LOSE")
    end
end

-- Air1601发送数据信息给Air780EPM。
local function airlink_sdata_Air780EPM()
    while 1 do
        -- 只发送设备信息，不发送时间
        local data = tostring(rtos.bsp())
        log.info("发送数据给对端设备", data, "当前airlink状态", airlink.ready())
        airlink.sdata(data)
        sys.wait(1000)
        log.info("ticks", mcu.ticks(), hmeta.chip(), hmeta.model(), hmeta.hwver())
        airlink.statistics()
    end
end

-- 一个简单的HTTP GET请求测试程序，用于判断Air1601的网络连接情况。
local function http_get_test()
    while true do
        sys.wait(10000)
        -- 本功能在2025.9.3
        log.info("网卡状态", netdrv.ready(socket.LWIP_USER0))
        -- 发起一个HTTP GET请求。
        log.info("发起HTTP GET请求", "https://httpbin.air32.cn/bytes/2048")
        local code, headers, body = http.request("GET", "https://httpbin.air32.cn/bytes/2048", nil, nil, {
            timeout = 9000,
            adapter = socket.LWIP_USER0
        }).wait()

        -- 打印HTTP请求的结果，包括响应码code和响应体长度#body。
        if code == 200 then
            log.info("HTTP请求成功", "响应码", code, "响应体长度", body and #body)
            sys.publish("打印网卡信息", "succeeded")
        else
            log.error("HTTP请求失败", "错误码", code)
            sys.publish("打印网卡信息", "failed")
        end
    end
end

-- 订阅airlink的SDATA事件，打印收到的信息。
local function airlink_sdata(data)
    -- 打印收到的信息。
    log.info("收到AIRLINK_SDATA!!", data)
    
    -- 检查是否是二维码信息
    if type(data) == "string" and data:find("AIRCLOUD_QR:") then
        -- 移除反引号和多余空格，确保URL完整
        local qr_url = data:match("AIRCLOUD_QR:%s*`?(.+)`?")
        if qr_url then
            -- 去除首尾空格
            qr_url = qr_url:gsub("^%s*",""):gsub("%s*$","")
            log.info("netdrv_4g", "收到二维码信息:", qr_url)
            sys.publish("aircloud_qrinfo", qr_url)
        end
        return
    end
    
    -- 检查是否是时间信息
    if type(data) == "string" and not data:find("MOBILE_INFO:") then
        -- 尝试从Air780EPM的时间信息中提取时间
        local time_str = data:match("(%a+ %a+ %d+ %d+:%d+:%d+ %d+)")
        if time_str then
            log.info("time", "从Air780EPM收到时间信息", time_str)
            -- 解析时间字符串，格式如 "Wed Mar 18 15:08:29 2026"
            local pattern = "(%a+) (%a+) (%d+) (%d+):(%d+):(%d+) (%d+)"
            local day, month, date, hour, min, sec, year = time_str:match(pattern)
            log.info("time", "解析结果", day, month, date, hour, min, sec, year)
            
            if day and month and date and year and hour and min and sec then
                -- 月份映射
                local months = {
                    Jan = 1, Feb = 2, Mar = 3, Apr = 4, May = 5, Jun = 6,
                    Jul = 7, Aug = 8, Sep = 9, Oct = 10, Nov = 11, Dec = 12
                }
                local month_num = months[month]
                log.info("time", "月份转换", month, "->", month_num)
                
                if month_num then
                    -- 记录时间信息
                    log.info("time", "收到时间信息", year, month_num, date, hour, min, sec)
                    -- 发布时间更新事件
                    sys.publish("AIR780_TIME_UPDATED", {
                        year = tonumber(year),
                        month = tonumber(month_num),
                        day = tonumber(date),
                        hour = tonumber(hour),
                        min = tonumber(min),
                        sec = tonumber(sec)
                    })
                    -- 注意：Air1601可能不支持rtos.set_time函数
                    if rtos.set_time then
                        local success = rtos.set_time(tonumber(year), tonumber(month_num), tonumber(date), 
                                                     tonumber(hour), tonumber(min), tonumber(sec))
                        log.info("time", "rtos.set_time返回值", success)
                        if success then
                            log.info("time", "时间同步成功", year, month_num, date, hour, min, sec)
                            print_time_details()
                        else
                            log.error("time", "时间同步失败")
                        end
                    else
                        log.warn("time", "Air1601不支持rtos.set_time函数，无法设置系统时间")
                    end
                else
                    log.error("time", "无法识别月份", month)
                end
            else
                log.error("time", "时间字符串解析失败")
            end
        end
    end
end

-- 订阅IP事件
sys.subscribe("IP_READY", ip_ready_func)
sys.subscribe("IP_LOSE", ip_lose_func)

-- 开启airlink
sys.taskInit(init_airlink_net)
-- Air1601发送数据信息给Air780EPM。
sys.taskInit(airlink_sdata_Air780EPM)
sys.taskInit(http_get_test)
-- 启动时间同步任务
sys.taskInit(time_sync_loop)
-- 订阅airlink的SDATA事件，打印收到的信息。
sys.subscribe("AIRLINK_SDATA", airlink_sdata)

-- 订阅传感器数据事件，发送给780EPM
sys.subscribe("SENSOR_DATA_TO_AIR780", function(data)
    log.info("netdrv_4g", "收到传感器数据，发送给780EPM:", data)
    if airlink and airlink.ready() then
        airlink.sdata(data)
        log.info("netdrv_4g", "传感器数据发送成功")
    else
        log.warn("netdrv_4g", "airlink未就绪，无法发送传感器数据")
    end
end)
