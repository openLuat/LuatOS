-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "timeDemo"
VERSION = "1.0"

--[[
本demo需要mqtt库, 大部分能联网的设备都具有这个库
mqtt也是内置库, 无需require
]]

-- sys库是标配
_G.sys = require("sys")
--[[特别注意, 使用mqtt库需要下列语句]]
_G.sysplus = require("sysplus")

sys.taskInit(function ()
        -- 等待联网
        sys.waitUntil("IP_READY")
        sys.wait(1000)
        -- 对于Cat.1模块, 移动/电信卡, 通常会下发基站时间,  那么sntp就不是必要的, 而联通卡通常不会下发, 就需要sntp了
        -- 对应ESP32系列模块, 固件默认也会执行sntp, 所以手动调用sntp也是可选的
        -- sntp内置了几个常用的ntp服务器, 也支持自选服务器
        while 1 do
            -- 使用内置的ntp服务器地址, 包括阿里ntp
            log.info("开始执行SNTP")
            socket.sntp()
            -- 自定义ntp地址
            -- socket.sntp("ntp.aliyun.com")
            -- socket.sntp({"baidu.com", "abc.com", "ntp.air32.cn"})
            -- 通常只需要几百毫秒就能成功
            local ret = sys.waitUntil("NTP_UPDATE", 5000)
            if ret then
                -- 以下是获取/打印时间的演示,注意时区问题
                log.info("sntp", "时间同步成功", "本地时间", os.date())
                log.info("sntp", "时间同步成功", "UTC时间", os.date("!%c"))
                log.info("sntp", "时间同步成功", "RTC时钟(UTC时间)", json.encode(rtc.get()))
                -- os.time(rtc.get()) 需要 2023.07.21 之后的版本, 因为月份的命名差异mon/month
                -- log.info("sntp", "时间同步成功", "utc时间戳", os.time(rtc.get()))
                log.info("sntp", "时间同步成功", "本地时间戳", os.time())
                local t = os.date("*t")
                log.info("sntp", "时间同步成功", "本地时间os.date() json格式", json.encode(t))
                log.info("sntp", "时间同步成功", "本地时间os.date(os.time())", os.time(t))
                -- log.info("sntp", "时间同步成功", "本地时间", os.time())
                -- 正常使用, 一小时一次, 已经足够了, 甚至1天一次也可以
                -- sys.wait(3600000) 
                -- 这里为了演示, 用5秒一次
                sys.wait(5000)
            else
                log.info("sntp", "时间同步失败")
                sys.wait(60000) -- 1分钟后重试
            end
    
            -- 时间戳, 精确到毫秒. 2023.11.15 新增
            -- 注意, 至少成功完成2次sntp,该时间戳才比较准确
            -- 如果仅完成了一次sntp, 时间戳比标准时间会慢一个网络延时的时长(10~500ms)不等
            if socket.ntptm then
                local tm = socket.ntptm()
                log.info("tm数据", json.encode(tm))
                log.info("时间戳", string.format("%u.%03d", tm.tsec, tm.tms))
                sys.wait(5000)
            end
        end
    
end)

sys.subscribe("NTP_ERROR", function()
    log.info("socket", "sntp error")
    -- socket.sntp()
end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
