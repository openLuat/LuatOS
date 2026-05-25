--[[
@module  ntp_app
@summary NTP时间同步模块
@version 1.1
@date    2026.05.19
@author  马亚丹 / 江访
@usage
核心逻辑：
1. 等待网络就绪（IP_READY事件，非轮询）
2. 网络就绪后开始NTP时间同步
3. 时间同步成功，获取本地时间和UTC时间
4. 按默认间隔循环同步

== 与其他模块的关系 ==
wifi_app 在 IP_READY 后通过 start_connectivity_verification() 等待 NTP_UPDATE
事件，以此判断"真实联网"是否成功。NTP_UPDATE 由底层固件在 socket.sntp()
成功后发布，ntp_app 和 wifi_app 同时等待该事件，互不冲突。
]]

-- 自定义NTP服务器列表，可选配置，默认使用内置的ntp.aliyun.com
local ntp_servers = {
    "ntp.aliyun.com",
    "ntp.air32.cn",
    "time1.cloud.tencent.com"
}

--[[
打印时间信息的工具函数
]]
local function print_time_detail()
    log.info("ntp_app", "本地时间字符串", os.date())
    log.info("ntp_app", "UTC时间字符串", os.date("!%c"))
    log.info("ntp_app", "格式化本地时间字符串", os.date("%Y-%m-%d %H:%M:%S"))
    log.info("ntp_app", "格式化UTC时间字符串", os.date("!%Y-%m-%d %H:%M:%S"))

    local rt = rtc.get()
    log.info("ntp_app", "RTC时钟(UTC)", json.encode(rt))
    log.info("ntp_app", "本地时间戳", os.time())

    local lt = os.date("*t")
    log.info("ntp_app", "本地时间结构", json.encode(lt))
    log.info("ntp_app", "结构时间转时间戳", os.time(lt))
end

--[[
打印高精度时间戳
]]
local function print_high_precision_time()
    local nt = socket.ntptm()
    if nt and nt.tsec then
        log.info("ntp_app", "高精度时间数据", json.encode(nt))
        log.info("ntp_app", "高精度时间戳", string.format("%u.%03d", nt.tsec, nt.tms))
    else
        log.warn("ntp_app", "高精度时间戳获取失败")
    end
end

--[[
NTP同步主逻辑
]]
local function ntp_sync_task()
    -- Air1601/Air1602需要显式设置默认网卡为STA
    local chip = (_G.project_config and _G.project_config.chip) or ""
    if chip:find("Air1601") or chip:find("Air1602") then
        socket.dft(socket.LWIP_STA)
    end

    -- 等待默认网卡就绪（IP_READY事件）
    -- 先检查当前状态，避免IP_READY在waitUntil之前已发布导致永久等待
    -- 使用 sys.waitUntil 直接等待事件，避免每秒轮询
    if not socket.adapter(socket.dft()) then
        log.info("ntp_app", "等待网络就绪...")
        sys.waitUntil("IP_READY")
    end
    log.info("ntp_app", "检测到IP_READY，默认网卡:", socket.dft())

    -- 网络就绪后开始NTP循环同步
    while true do
        log.info("ntp_app", "开始NTP时间同步")
        -- 使用默认NTP服务器（ntp.aliyun.com）
        socket.sntp()

        -- 等待同步结果（NTP_UPDATE由底层在SNTP成功后发布）
        local success = sys.waitUntil("NTP_UPDATE", 5000)

        if success then
            log.info("ntp_app", "时间同步成功")
            print_time_detail()
            print_high_precision_time()
            -- 同步成功后等待5分钟再次同步
            sys.wait(300 * 1000)
        else
            log.warn("ntp_app", "时间同步失败，10秒后重试")
            -- 同步失败等待10秒重试
            sys.wait(10 * 1000)
        end
    end
end

-- 订阅NTP错误消息
sys.subscribe("NTP_ERROR", function(err_info)
    log.error("ntp_app", "同步过程发生错误", err_info or "未知错误")
end)

-- 启动NTP同步任务
sys.taskInit(ntp_sync_task)
