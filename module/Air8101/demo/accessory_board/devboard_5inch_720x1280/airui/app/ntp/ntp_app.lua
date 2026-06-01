--[[
@module  ntp_test
@summary ntp_test测试功能模块
@version 1.0
@date    2025.10.24
@author  马亚丹
@usage
本demo演示的功能为：使用Air8000开发板，演示用ntp网络对时后,获取本地时间和UTC时间的功能
核心逻辑：

1.判断是否联网，
2.网络就绪后开始时间同步
3.时间同步成功，获取本地时间和UTC时间，按默认间隔时间循环打印获取的时间信息
4.时间同步失败，打印提醒



]]

-- 自定义NTP服务器列表，可选配置，默认使用内置的ntp服务器地址ntp.aliyun.com
local ntp_servers = {
    "ntp.aliyun.com",
    "ntp.air32.cn",
    "time1.cloud.tencent.com"
}

--本地时间是指:当前时区的时间，默认是东八区北京时间，可以通过rtc.timezone接口查询或者设置时区
--UTC时间是指：0时区的时间
--东八区的时间是在UTC时间的基础上增加8个小时

-- 打印时间信息的工具函数
local function print_time_details()
    --设置为东3区时间
    --rtc.timezone(12)
    --获取东3区的时间字符串
    --东3区时间字符串 Fri Oct 24 12:01:20 2025
    --log.info("sntp", "东3区时间字符串", os.date())


    -- 获取本地时间字符串
    -- 本地时间字符串 Fri Oct 24 17:01:15 2025
    log.info("sntp", "本地时间字符串", os.date())

    -- 获取UTC时间字符串
    -- UTC时间字符串  Fri Oct 24 09:01:15 2025
    log.info("sntp", "UTC时间字符串", os.date("!%c"))

    -- 格式化本地时间字符串
    -- 本地时间字符串 2025-10-24 17:01:15
    log.info("sntp", "格式化本地时间字符串", os.date("%Y-%m-%d %H:%M:%S"))


    -- 格式化UTC时间字符串
    -- UTC时间字符串 2025-10-24 09:01:15
    log.info("sntp", "格式化UTC时间字符串", os.date("!%Y-%m-%d %H:%M:%S"))


    -- RTC时钟原始数据（UTC时间）
    local rtc_time = rtc.get()
    -- RTC时钟(UTC) {"year":2025,"min":1,"hour":9,"mon":10,"sec":15,"day":24}
    log.info("sntp", "RTC时钟(UTC)", json.encode(rtc_time))


    -- 本地时间戳（秒级）
    --本地时间戳 1761296475
    log.info("sntp", "本地时间戳", os.time())

    -- 获取本地时间的table
    -- 本地时间结构 {"wday":6,"min":1,"yday":297,"hour":17,"isdst":false,"year":2025,"month":10,"sec":15,"day":24}

    local local_struct_time = os.date("*t")
    log.info("sntp", "本地时间结构", json.encode(local_struct_time))
    --结构时间转时间戳 1761325275
    log.info("sntp", "结构时间转时间戳", os.time(local_struct_time))
end

-- 打印高精度时间戳
local function print_high_precision_time()
    local ntp_time = socket.ntptm()
    if ntp_time and ntp_time.tsec then
        --tm数据 {"sms":89,"tms":320,"vaild":true,"tsec":1761296475,"lms":231,"ndeley":28,"lsec":18,"ssec":1761296457}
        log.info("tm数据", json.encode(ntp_time))
        -- 格式化：秒.毫秒
        --高精度时间戳 1761296475.320
        log.info("sntp", "高精度时间戳", string.format("%u.%03d", ntp_time.tsec, ntp_time.tms))
    else
        log.warn("sntp", "高精度时间戳获取失败")
    end
end

-- SNTP同步主逻辑
local function sntp_sync_loop()
    --查看网卡适配器的联网状态是否IP_READY,true表示已经准备好可以联网了,false暂时不可以联网
    while not socket.adapter(socket.dft()) do
        log.warn("sntp", "wait IP_READY", socket.dft())
        -- 在此处阻塞等待默认网卡连接成功的消息"IP_READY"
        -- 或者等待1秒超时退出阻塞等待状态;
        -- 注意：此处的1000毫秒超时不要修改的更长；
        -- 因为当使用exnetif.set_priority_order配置多个网卡连接外网的优先级时，会隐式的修改默认使用的网卡
        -- 当exnetif.set_priority_order的调用时序和此处的socket.adapter(socket.dft())判断时序有可能不匹配
        -- 此处的1秒，能够保证，即使时序不匹配，也能1秒钟退出阻塞状态，再去判断socket.adapter(socket.dft())
        sys.waitUntil("IP_READY", 1000)
    end

    -- 检测到了IP_READY消息，设置默认网络适配器编号
    log.info("sntp", "recv IP_READY", socket.dft())


    while true do
        log.info("sntp", "开始同步：")
        -- 方式1：使用自定义服务器列表
        -- log.info("sntp", "开始同步，服务器列表：", json.encode(ntp_servers))
        -- 选择自己要用的的服务器
        --socket.sntp(ntp_servers[2])

        -- 方式2： 使用默认的ntp服务器地址：ntp.aliyun.com
        socket.sntp()

        -- 等待同步结果（成功：NTP_UPDATE，失败：超时）
        local sync_success = sys.waitUntil("NTP_UPDATE", 5000)

        if sync_success then
            --ntp同步成功之后，已经自动将系统时间设置为本地时间
            --在此处的脚本中，不需要再调用任何时间设置接口去手动设置时间
            --本地时间：默认为东八区北京时间,如果使用rtc.timezone(zone)设置过本地时间，则本地时间为自己设置过的时区对应的时间
            -- 同步成功：打印时间信息
            log.info("sntp", "时间同步成功")
            print_time_details()
            print_high_precision_time()
            --时间同步成功
            --再等待1小时再次发起下次时间同步，这里的等待时长可以按自己的需求修改。
            sys.wait(3600*1000)
        else
            log.warn("sntp", "时间同步失败")
            --时间同步失败
            --再等待10秒重新发起时间同步，这里的等待时长可以按自己的需求修改。
            sys.wait(10*1000)
        end
    end
end

-- 订阅NTP错误消息
sys.subscribe("NTP_ERROR", function(err_info)
    log.error("sntp", "同步过程发生错误", err_info or "未知错误")
end)

-- 启动SNTP同步任务
sys.taskInit(sntp_sync_loop)
