
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "sntpdemo"
VERSION = "1.0.0"

-- 统一联网函数
sys.taskInit(function()
    -----------------------------
    -- 统一联网函数, 可自行删减
    ----------------------------
    if wlan and wlan.connect then
        -- wifi 联网, Air8101系列均支持，ssid、password修改为自己的wifi参数
        local ssid = "momowifi"
        local password = "abc123456"
        log.info("wifi", ssid, password)
        wlan.init()
        wlan.setMode(wlan.STATION) -- 默认也是这个模式,不调用也可以
        device_id = wlan.getMac()
        wlan.connect(ssid, password, 1)
    else
         -- 其他不认识的bsp, 循环提示一下吧
         while 1 do
            sys.wait(1000)
            log.info("bsp", "本bsp可能未适配网络层, 请查证")
        end
    end
    -- 默认都等到联网成功
    sys.waitUntil("IP_READY")
    sys.publish("net_ready", device_id)
end)

sys.taskInit(function()
    -- 等待联网
    local ret, device_id = sys.waitUntil("net_ready")
    sys.wait(1000)
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
            log.info("sntp", "时间同步成功", "本地时间戳", os.time())
            local t = os.date("*t")
            log.info("sntp", "时间同步成功", "本地时间os.date() json格式", json.encode(t))
            log.info("sntp", "时间同步成功", "本地时间os.date(os.time())", os.time(t))
            -- 正常使用, 一小时一次, 已经足够了, 甚至1天一次也可以
            -- sys.wait(3600000) 
            -- 这里为了演示, 用5秒一次
            sys.wait(5000)
        else
            log.info("sntp", "时间同步失败")
            sys.wait(60000) -- 1分钟后重试
        end
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