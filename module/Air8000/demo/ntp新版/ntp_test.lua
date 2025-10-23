-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "sntpdemo"
VERSION = "1.0.0"

--[[
核心逻辑：

1.判断是否联网，
2.网络就绪后开始时间同步
3.时间同步成功，获取本地时间和UTC时间，循环默认时间打印一次
4.时间同步失败，进行重试获取



]]

-- 配置常量：集中管理参数，方便后续调整
local CONFIG = {
    -- 等待NTP同步结果的超时时间(ms)
    sntp_timeout = 5000,    
     -- 同步成功后，下次同步间隔(ms)，默认15秒
    success_interval = 15000, 
      -- 同步失败后，重试间隔(ms)，默认1分钟
    fail_retry_interval = 60000, 
    -- 失败重试最大间隔(ms)，避免无限递增，默认5分钟
    max_retry_backoff = 300000,  
    -- 自定义NTP服务器列表，可选配置，默认使用内置的ntp服务器地址
    ntp_servers = {              
        "ntp.aliyun.com",
        "ntp.air32.cn",
        "time1.cloud.tencent.com"
    }
}

-- 打印时间信息的工具函数：抽离重复逻辑，提高可读性
local function print_time_details()
    -- 获取本地时间字符串
    -- 本地时间字符串 Tue Sep 30 00:22:21 2025
    log.info("sntp", "本地时间字符串", os.date())

    -- 获取UTC时间字符串
    -- UTC时间字符串 Mon Sep 29 16:22:21 2025
    log.info("sntp", "UTC时间字符串", os.date("!%c"))

    -- 格式化本地时间字符串
    -- 本地时间字符串 2025-09-30 00:22:21
    log.info("sntp", "格式化本地时间字符串", os.date("%Y-%m-%d %H:%M:%S"))


    -- 格式化UTC时间字符串
    -- UTC时间字符串 2025-09-29 16:22:21
    log.info("sntp", "格式化UTC时间字符串", os.date("!%Y-%m-%d %H:%M:%S"))


    -- RTC时钟原始数据（UTC时间）
    local rtc_time = rtc.get()
    log.info("sntp", "RTC时钟(UTC)", json.encode(rtc_time))


    -- 本地时间戳（秒级）
    log.info("sntp", "本地时间戳", os.time())

    -- 获取本地时间的table
    -- 本地时间table {"wday":3,"min":22,"yday":273,"hour":0,"isdst":false,"year":2025,"month":9,"sec":21,"day":30}
    local local_struct_time = os.date("*t")
    log.info("sntp", "本地时间结构", json.encode(local_struct_time))
    log.info("sntp", "结构时间转时间戳", os.time(local_struct_time))
end

-- 打印高精度时间戳（如果支持）
local function print_high_precision_time()
    if not socket.ntptm then
        return -- 不支持则跳过
    end
    local ntp_time = socket.ntptm()
    if ntp_time and ntp_time.tsec then
        log.info("tm数据", json.encode(ntp_time))
        -- 格式化：秒.毫秒
        log.info("sntp", "高精度时间戳", string.format("%u.%03d", ntp_time.tsec, ntp_time.tms))
    else
        log.warn("sntp", "高精度时间戳获取失败")
    end
end

-- SNTP同步主逻辑
local function sntp_sync_loop()
    -- 等待网络就绪（IP获取成功）
    if not sys.waitUntil("IP_READY", 30000) then -- 30秒超时，避免无限等待
        log.error("sntp", "网络未就绪，退出同步")
        return
    end
    log.info("sntp", "网络就绪，开始时间同步流程")

    local fail_retry_count = 0 -- 失败重试计数，用于动态调整间隔

    while true do
        -- 执行SNTP同步，使用自定义服务器列表
        -- log.info("sntp", "开始同步，服务器列表：", json.encode(CONFIG.ntp_servers))
        -- socket.sntp(CONFIG.ntp_servers)
        log.info("sntp", "开始同步：")
        -- 使用内置的ntp服务器地址
        socket.sntp()

        -- 等待同步结果（成功：NTP_UPDATE，失败：超时）
        local sync_success = sys.waitUntil("NTP_UPDATE", CONFIG.sntp_timeout)

        if sync_success then
            -- 同步成功：重置失败计数，打印时间信息
            fail_retry_count = 0
            log.info("sntp", "时间同步成功")
            print_time_details()
            print_high_precision_time()
            -- 等待下次同步（使用成功间隔）
            sys.wait(CONFIG.success_interval)
        else
            -- 同步失败：累加失败计数，动态调整重试间隔
            fail_retry_count = fail_retry_count + 1
            local retry_interval = math.min(
                CONFIG.fail_retry_interval * (2 ^ (fail_retry_count - 1)), -- 指数递增
                CONFIG.max_retry_backoff                                   -- 不超过最大间隔
            )
            log.warn("sntp", "时间同步失败", "重试次数：", fail_retry_count, "下次重试间隔(ms)：", retry_interval)
            sys.wait(retry_interval)
        end
    end
end

-- 订阅NTP错误消息，补充错误日志
sys.subscribe("NTP_ERROR", function(err_info)
    log.error("sntp", "同步过程发生错误", err_info or "未知错误")
end)

-- 启动SNTP同步任务
sys.taskInit(sntp_sync_loop)
