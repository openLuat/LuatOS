--[[
@module active_mode
@summary 已激活模式（通过 create.lua 通道上报）
@version 3.0
@date    2026.07.17
@usage
已激活模式，适用于常规模式、智能模式和 GPS定位模式。
通过 create.lua 的 NET_SENT_RDY 通道上报数据。
]]

local config = require("config")
local kvstore = require("kvstore")
local tools = require("tools")
local location = require("location")
local gsensor = require("gsensor")
local battery = require("battery")
local remote = require("remote")
local create = require("create")
local lowpower = require("lowpower_app")
local exgnss = require("exgnss")
local excloud = require("excloud")

-- 本次上报计算出的上报间隔（秒），供 779 上报与主循环等待共用
-- 由 collect_data_and_report 计算一次，避免 get_smart_mode_interval 被重复调用导致无运动次数重复累加
local last_calc_interval = 0

-- 寻宠模式 GPS 定位成功标志：本次上报 gps_status==2 时为 true，否则 false
-- 主循环据此决定寻宠模式的下一次上报间隔：GPS成功→5s高频，失败→30s LBS保底
local find_gps_ok = false

-- ====== 方案B：震动触发立即上报 + 冷却期防抖 ======
-- 震动事件名（gsensor 震动回调发布，主循环 waitUntil 监听）
local MOTION_EVENT = "MOTION_EVENT"
-- 震动上报冷却期（秒）：从 config.SENSOR_CONFIG.MOTION_COOLDOWN 读取（网页可配置，默认600秒=10分钟）
local function get_motion_cooldown()
    return (config.SENSOR_CONFIG and config.SENSOR_CONFIG.MOTION_COOLDOWN) or 600
end
-- 冷却期截止时间戳（秒）：震动立即上报时设为 now+cooldown，0=不在冷却期
local cooldown_until = 0
-- ==============================================

-- 判断当前是否处于震动上报冷却期
local function in_motion_cooldown()
    if cooldown_until <= 0 then
        return false
    end
    local now_sec = os.time()
    if now_sec >= cooldown_until then
        -- 冷却期已到点，自动解除
        cooldown_until = 0
        return false
    end
    return true
end

-- 获取当前工作模式
local function get_work_mode()
    return kvstore.get_work_mode()
end

-- 构建消息框架
local function build_msg(msg_type)
    local imei = mobile.imei() or "000000000000000"
    local ts = os.time()
    return {
        msg_id = imei .. "-" .. ts,
        imei = imei,
        ts = ts,
        type = msg_type,
        data = {}
    }
end

-- 上报开机信息
local function report_startup()
    local msg = build_msg("startup")
    msg.data = {
        imei = mobile.imei() or "000000000000000",
        iccid = mobile.iccid(),
        version = VERSION or "unknown",
        start_time = os.time()
    }
    create.send(json.encode(msg))
    log.info("active_mode", "已上报 startup")
end

-- 计算当前驻留频段（参考 aircloud_heart，通过 EARFCN 判断）
local function get_current_band()
    local scell = mobile.scell()
    if not scell or not scell.earfcn then return nil end
    local e = scell.earfcn
    if e <= 599 then return 1
    elseif e <= 1949 then return 3
    elseif e <= 2649 then return 5
    elseif e <= 3449 then return 7
    elseif e <= 3799 then return 8
    elseif e <= 6449 then return 20
    elseif e <= 38249 then return 38
    elseif e <= 38649 then return 39
    elseif e <= 39649 then return 40
    elseif e <= 41589 then return 41 end
    return nil
end

-- 解析卫星信息（GSV）：最强4颗卫星CN值、搜星总数、可见卫星数
local function get_gsv_report()
    local report = { sat_total = 0, sat_visible = 0, top4_cn = "" }
    local gsv = exgnss.gsv()
    if not gsv or not gsv.sats then return report end
    report.sat_total = gsv.total_sats or #gsv.sats
    -- 过滤出有信噪比（snr）的可见卫星
    local cn_list = {}
    for _, s in ipairs(gsv.sats) do
        if s.snr and s.snr > 0 then
            table.insert(cn_list, s.snr)
        end
    end
    report.sat_visible = #cn_list
    table.sort(cn_list, function(a, b) return a > b end)
    local top = {}
    for i = 1, math.min(4, #cn_list) do
        table.insert(top, tostring(cn_list[i]))
    end
    report.top4_cn = table.concat(top, ",")
    return report
end

-- 获取开机原因（映射为可读字符串）
-- pm.lastReson() 返回的数字含义随模组/唤醒方式变化，以下为常见映射，可按实际硬件校准
local function get_boot_reason()
    local r1 = pm.lastReson() or 0
    if r1 == 0 then
        return "power_on"      -- 上电开机
    elseif r1 == 1 then
        return "soft_reset"    -- 软件复位
    elseif r1 == 2 then
        return "wakeup"        -- 引脚/中断唤醒
    elseif r1 == 5 then
        return "powerkey"      -- 按键开机
    end
    return tostring(r1)
end

-- 将 data 字段转换为 AirCloud TLV 字段数组（供 create.send_aircloud 发送）
-- 无标准 field_meaning 的字段从 1290 起自定义编号
-- 注意：excloud 编码 ASCII 空字符串会失败导致整包发送失败，因此空值字段一律跳过
local function build_aircloud_tlv(d)
    local FM = excloud.FIELD_MEANINGS
    local DT = excloud.DATA_TYPES
    local data = {}

    -- 通用字段（所有定位方式都上报）
    table.insert(data, { field_meaning = 1290, data_type = DT.INTEGER, value = d.work_mode or 0 })               -- 工作模式
    table.insert(data, { field_meaning = FM.VOLTAGE, data_type = DT.INTEGER, value = d.vbat or 0 })              -- 电池电压(mV)
    table.insert(data, { field_meaning = 1291, data_type = DT.INTEGER, value = d.bat_change or 0 })              -- 充电状态
    -- 信号强度（CSQ，0-31 正整数，直接上报）
    table.insert(data, { field_meaning = FM.SIGNAL_STRENGTH_4G, data_type = DT.INTEGER, value = d.signal or 0 })
    -- 位置：解析 "lat,lng" 为经度/纬度分开上报（512=经度 513=纬度，ASCII）
    if d.gps and d.gps ~= "" then
        local gps_str = d.gps
        local lat, lng = gps_str:match("^([%d%.%-]+),([%d%.%-]+)$")
        if lat and lng then
            table.insert(data, { field_meaning = FM.GNSS_LONGITUDE, data_type = DT.ASCII, value = tostring(lng) })
            table.insert(data, { field_meaning = FM.GNSS_LATITUDE, data_type = DT.ASCII, value = tostring(lat) })
        end
    end
    table.insert(data, { field_meaning = FM.LOCATION_METHOD, data_type = DT.ASCII, value = tostring(d.gps_status or 0) })
    -- 字符串字段非空才上报，避免空串编码失败
    if d.band and d.band ~= "" then
        table.insert(data, { field_meaning = FM.SERVING_CELL, data_type = DT.ASCII, value = d.band })            -- 驻留频段
    end
    if d.chip_model and d.chip_model ~= "" then
        table.insert(data, { field_meaning = FM.COMPONENT_MODEL, data_type = DT.ASCII, value = d.chip_model })   -- 元器件型号
    end
    if d.boot_reason and d.boot_reason ~= "" then
        table.insert(data, { field_meaning = FM.BOOT_REASON, data_type = DT.ASCII, value = d.boot_reason })      -- 开机原因
    end
    table.insert(data, { field_meaning = FM.WAKE_INTERVAL, data_type = DT.INTEGER, value = d.wake_interval or 0 }) -- 定时唤醒间隔
    if d.iccid and d.iccid ~= "" then
        table.insert(data, { field_meaning = FM.SIM_ICCID, data_type = DT.ASCII, value = d.iccid })              -- ICCID
    end
    -- 卫星信息：仅 GPS 定位成功（gps_status=2）才上报
    if d.gps_status == 2 then
        if d.top4_cn and d.top4_cn ~= "" then
            table.insert(data, { field_meaning = FM.GNSS_CN, data_type = DT.ASCII, value = d.top4_cn })          -- 最强4星CN
        end
        table.insert(data, { field_meaning = FM.SATELLITES_TOTAL, data_type = DT.INTEGER, value = d.sat_total or 0 }) -- 搜星总数
        table.insert(data, { field_meaning = FM.SATELLITES_VISIBLE, data_type = DT.INTEGER, value = d.sat_visible or 0 }) -- 可见卫星数
    end

    return data
end

-- 智能模式上报间隔计算（方案B）
-- 震动不清零叠加计数，叠加一直向上递增（开机清零），封顶 SMART_AWAY_STATIC_MAX
-- 震动只触发"立即上报 + 冷却期防抖"，由主循环 MOTION_EVENT 处理
local function get_smart_mode_interval()
    local motion_detect_on = config.SENSOR_CONFIG and config.SENSOR_CONFIG.MOTION_DETECT_ON
    local is_moving = motion_detect_on and gsensor.is_moving() or false
    local no_motion_count = kvstore.get_no_motion_count() or 0
    local interval = 0

    -- 方案B：不再因运动状态清零叠加，统一走叠加逻辑
    -- 运动中基础间隔用 MOVING，静止用 STATIC（服务端 smart_interval 同时覆盖两者）
    if is_moving then
        interval = config.REPORT_INTERVAL.SMART_AWAY_MOVING
    else
        interval = config.REPORT_INTERVAL.SMART_AWAY_STATIC
    end
    no_motion_count = no_motion_count + 1
    local inc = no_motion_count * config.REPORT_INTERVAL.SMART_AWAY_STATIC_INCREMENT
    interval = math.min(interval + inc, config.REPORT_INTERVAL.SMART_AWAY_STATIC_MAX)

    kvstore.set_smart_interval(interval)
    kvstore.set_no_motion_count(no_motion_count)
    return interval
end

-- 计算本次上报间隔（秒）：供 779(wake_interval) 上报与主循环等待共用
-- 优先级：充电60s > 服务端自定义间隔 > 低电量 > 各模式间隔
local function calc_report_interval()
    local work_mode = get_work_mode()
    local is_low_power = kvstore.get_low_power_mode() or false
    local interval = config.REPORT_INTERVAL.PERFORMANCE

    local vbus_state = tools.get_vbus_state()
    if vbus_state == 1 then
        interval = config.REPORT_INTERVAL.CHARGING or 60
    else
        if is_low_power and work_mode ~= config.DEVICE_MODE.FIND then
            interval = config.REPORT_INTERVAL.LOW_POWER
        else
            if work_mode == config.DEVICE_MODE.PERFORMANCE then
                interval = config.REPORT_INTERVAL.PERFORMANCE
            elseif work_mode == config.DEVICE_MODE.SMART then
                interval = get_smart_mode_interval()
            elseif work_mode == config.DEVICE_MODE.FIND then
                interval = config.FIND_MODE_CONFIG.REPORT_INTERVAL
            end
        end
    end

    -- 服务端下发的自定义上报间隔优先（vbus充电60s除外）
    local custom_interval = kvstore.get_report_interval()
    if custom_interval and vbus_state ~= 1 then
        interval = custom_interval
        log.info("active_mode", "使用自定义上报间隔:", interval, "秒")
    end

    return interval
end

-- 震动唤醒后强制下一次上报走 GPS（不依赖 is_moving 超时时序）
-- 震动唤醒 → MOTION_EVENT → motion_wake=true → 置位 → collect 读取后清除
-- 注意：必须在 collect_data_and_report 之前声明（Lua local 需先声明后引用）
local force_gps_next_report = false

-- 数据收集与上报
local function collect_data_and_report()
    log.info("active_mode", "开始收集数据")

    -- 唤醒全功率模式（低功耗等待后恢复）
    pm.power(pm.WORK_MODE, 0)

    -- 等待网络就绪（最多30秒）
    local network_timeout = 0
    local MAX_NETWORK_WAIT = 30
    while not socket.adapter(socket.dft()) do
        log.warn("active_mode", "wait IP_READY", socket.dft())
        sys.waitUntil("IP_READY", 1000)
        network_timeout = network_timeout + 1
        if network_timeout >= MAX_NETWORK_WAIT then
            log.error("active_mode", "网络连接超时，跳过本次上报")
            return
        end
    end
    log.info("active_mode", "网络已就绪")

    local work_mode = get_work_mode()

    -- 更新电源状态和 LED
    -- 黄灯 GPIO27：插入充电器常亮（充满或拔电灭）
    -- 绿灯 GPIO26：充电完成(充满)常亮；GPS定位模式慢闪(由上报完成处触发，10秒自动灭)
    local vbus_state, is_charge = tools.update_power_state()
    local battery_data_led = battery.get_data()
    local is_full = battery_data_led and battery_data_led.level and battery_data_led.level >= 99
    if vbus_state == 1 then
        if is_full then
            tools.yellowLed_OFF()
            tools.greenLed_ON()   -- 充满：绿灯常亮，黄灯灭
        else
            tools.yellowLed_ON()  -- 充电中：黄灯常亮
            -- 未充满：绿灯保持 GPS 定位模式慢闪或关闭
            if not tools.greenLed_is_blinking() then
                tools.greenLed_OFF()
            end
        end
    else
        tools.yellowLed_OFF()     -- 拔电：黄灯灭
        -- 拔电：绿灯充满常亮解除；若 GPS 定位模式慢闪中则保留
        if not tools.greenLed_is_blinking() then
            tools.greenLed_OFF()
        end
    end

    -- 低电量检测
    local is_low_power = false
    local battery_data = battery.force_check()
    if battery_data and battery_data.level then
        is_low_power = battery_data.level < config.ALARM_THRESHOLD.BATTERY_CRITICAL
        kvstore.set_low_power_mode(is_low_power)
    end

    -- 采集定位数据
    local is_moving = config.SENSOR_CONFIG and config.SENSOR_CONFIG.MOTION_DETECT_ON and gsensor.is_moving() or false
    -- 震动唤醒触发的上报：强制走 GPS（不依赖 is_moving 超时时序）
    -- 两个来源：
    --   1. force_gps_next_report：主循环 motion_wake=true 置位（正常模式路径）
    --   2. gsensor.consume_pending_gps()：interrupt_handler/set_motion_state 置位（含低功耗唤醒路径）
    -- 同时临时忽略低电量省电限制：震动定位是用户主动行为，应优先 GPS
    if force_gps_next_report or gsensor.consume_pending_gps() then
        force_gps_next_report = false
        is_moving = true
        is_low_power = false
        log.info("active_mode", "震动唤醒上报，强制 GPS 定位")
    end
    local loc_data = location.get_location(work_mode, is_low_power, is_moving)

    -- 信号强度（CSQ，范围 0-31，值越大信号越好；99=无信号）
    local signal = mobile.csq() or 0

    -- 额外上报字段
    local gsv = get_gsv_report()
    local boot_reason = get_boot_reason()
    local cur_band = get_current_band()
    -- 驻留频段格式化为 "LTE B{n}"
    local band_str = cur_band and ("LTE B" .. cur_band) or ""
    -- 779(wake_interval)：上报本次实际使用的上报间隔（秒）
    -- 存入 last_calc_interval 供主循环等待复用，避免重复调用 get_smart_mode_interval
    last_calc_interval = calc_report_interval()
    local wake_interval = last_calc_interval

    -- 构建 property/report 消息
    local msg = build_msg("property_report")
    local gps_str = loc_data and loc_data.gps or ""
    local gps_status = loc_data and loc_data.gps_status or 0

    msg.data = {
        bat_change = battery.is_charging() and 1 or 0,
        vbat = battery_data and battery_data.voltage or 0,
        gps = gps_str,
        gps_status = gps_status,
        signal = signal,
        work_mode = work_mode,
        position_active_report = 1,
        iccid = mobile.iccid(),
        chip_model = "Air8202",
        boot_reason = boot_reason,
        band = band_str,
        wake_interval = wake_interval,
        top4_cn = gsv.top4_cn,
        sat_total = gsv.sat_total,
        sat_visible = gsv.sat_visible
    }

    local payload = json.encode(msg)
    log.info("active_mode", "========== 上报数据 ==========")
    log.info("active_mode", "msg_id:", msg.msg_id)
    log.info("active_mode", "type:", msg.type)
    log.info("active_mode", "work_mode:", work_mode, "(0=常规 1=智能 2=GPS定位)")
    log.info("active_mode", "vbat:", msg.data.vbat, "mV")
    log.info("active_mode", "bat_change:", msg.data.bat_change, "(1=充电)")
    log.info("active_mode", "signal:", msg.data.signal)
    log.info("active_mode", "gps:", msg.data.gps ~= "" and msg.data.gps or "nil")
    log.info("active_mode", "gps_status:", msg.data.gps_status, "(2=GPS 3=失败 4=免费基站 5=付费基站)")
    log.info("active_mode", "iccid:", msg.data.iccid)
    log.info("active_mode", "chip_model:", msg.data.chip_model)
    log.info("active_mode", "boot_reason:", msg.data.boot_reason)
    log.info("active_mode", "band:", msg.data.band)
    log.info("active_mode", "top4_cn:", msg.data.top4_cn, "sat_total:", msg.data.sat_total, "sat_visible:", msg.data.sat_visible)
    log.info("active_mode", "payload:", payload)
    log.info("active_mode", "==============================")
    create.send(payload)
    log.info("active_mode", "数据已通过云通道发送(json)")

    -- AirCloud 通道：以 TLV 形式上报（其余字段不含 msg_id/type/ts/imei）
    create.send_aircloud(build_aircloud_tlv(msg.data))
    log.info("active_mode", "数据已通过 AirCloud TLV 发送")

    -- 记录上报时间
    kvstore.set_last_report_time(os.time())

    -- GPS定位模式（GNSS开启）：绿灯慢闪10秒（1Hz），10秒后自动灭；
    -- 期间若再次上报则自动重新计时10秒（本函数每次上报都会调用 greenLed_blink 重启计时）
    -- 充满状态优先（绿灯常亮），不触发慢闪
    local is_full_now = battery_data and battery_data.level and battery_data.level >= 99
    if work_mode == config.DEVICE_MODE.FIND and not is_full_now then
        tools.greenLed_blink(10)
    end

    -- 记录寻宠模式 GPS 定位成功标志（供主循环决定下次上报间隔）
    if work_mode == config.DEVICE_MODE.FIND then
        find_gps_ok = (gps_status == 2)
        log.info("active_mode", "寻宠模式 GPS 定位成功标志:", tostring(find_gps_ok))
    end

    log.info("active_mode", "数据上报完成")
end

-- 低电量监测任务（每分钟检测一次，低于阈值发布 BATTERY_LOW）
local function battery_monitor_task()
    while true do
        sys.wait(60000)
        local battery_data = battery.force_check()
        if battery_data and battery_data.level then
            if battery_data.level < config.ALARM_THRESHOLD.BATTERY_LOW then
                log.info("active_mode", "低电量:", battery_data.level, "%, 发布BATTERY_LOW")
                kvstore.set_low_power_mode(true)
                sys.publish("BATTERY_LOW", battery_data.level)
            end
        end
    end
end

-- 主循环
local function main_loop()
    log.info("active_mode", "进入主循环")

    -- 开机清零静止累加计数，确保智能模式每次开机从基础间隔起步
    kvstore.set_no_motion_count(0)

    -- 注册震动回调：DA221 震动（过2000ms限流）时发布 MOTION_EVENT，
    -- 主循环 waitUntil 收到后立即上报（震动触发定位）
    gsensor.on_vibration(function()
        log.info("active_mode", "检测到震动，发布 MOTION_EVENT")
        sys.publish(MOTION_EVENT)
    end, 2000)

    -- 初始化 LED
    if tools and tools.init_led then
        tools.init_led()
    end

    -- 启动低电量监测
    sys.taskInit(battery_monitor_task)

    -- 加载云平台连接模块（触发连接，由 create.lua 统一管理）
    -- 等待云平台连接成功后再上报开机
    sys.waitUntil("CLOUD_CONNECTED", 30000)
    log.info("active_mode", "云平台连接成功")
    report_startup()
    log.info("active_mode", "开机上报完成，进入主循环")

    -- ====== 寻宠模式：GPS 定位成功事件驱动 5s 高频上报 + 30s LBS 保底 ======
    -- 5s 定时器：GPS 定位成功后每 5 秒上报一次（高频追踪）
    -- 用 sys.timerLoopStart（循环型），由 LOCATION_SUCCESS / GNSS_STATE FIXED 事件启动/重启，
    -- GNSS_STATE LOSE 时停止，回退 30s LBS 保底
    local find_5s_timer = nil
    -- 上报进行中标志：防止 5s 高频与 30s 保底在上一轮上报未完成时重复触发任务堆积
    -- （网络等待最长 30s，可能超过 5s 定时周期）
    local find_reporting = false

    -- 5s 循环定时器回调：GPS 已定位成功则上报，否则跳过（30s LBS 保底负责兜底）
    local function find_timer_5s()
        if get_work_mode() ~= config.DEVICE_MODE.FIND then return end
        if not find_gps_ok then return end
        if find_reporting then return end
        find_reporting = true
        log.info("active_mode", "寻宠5s定时器：GPS已定位成功，高频上报")
        sys.taskInit(function()
            local ok, err = pcall(collect_data_and_report)
            find_reporting = false
            if not ok then log.error("active_mode", "寻宠5s上报异常:", err) end
        end)
    end

    -- GPS 定位成功事件触发：置成功标志 + 启动/重启 5s 高频循环定时器
    -- 双事件源（LOCATION_SUCCESS + GNSS_STATE FIXED）保证触发可靠：
    --   LOCATION_SUCCESS 是业务级事件（需 exgnss.rmc 就绪），GNSS_STATE FIXED 是底层事件
    -- 重复触发无副作用：先停止旧循环再启新循环，等价于重置 5s 计时起点
    local function find_on_gps_success()
        if get_work_mode() ~= config.DEVICE_MODE.FIND then return end
        log.info("active_mode", "收到GPS定位成功事件，启动5s高频上报")
        find_gps_ok = true
        if find_5s_timer then
            sys.timerStop(find_5s_timer)
        end
        find_5s_timer = sys.timerLoopStart(find_timer_5s, 5000)
    end

    -- GPS 信号丢失（GNSS_STATE LOSE）：停止 5s 高频，回退 30s LBS 保底
    local function find_on_gps_lose()
        if get_work_mode() ~= config.DEVICE_MODE.FIND then return end
        log.info("active_mode", "GPS信号丢失，停止5s高频，回退30s LBS保底")
        find_gps_ok = false
        if find_5s_timer then
            sys.timerStop(find_5s_timer)
            find_5s_timer = nil
        end
    end

    -- 30s 定时器：每 30 秒检测 GPS；未定位成功则上报 LBS 保底，成功则不操作
    local function find_timer_30s()
        if get_work_mode() ~= config.DEVICE_MODE.FIND then return end
        local fix = exgnss.is_fix and exgnss.is_fix() or false
        if fix then
            log.info("active_mode", "寻宠30s定时器：GPS已定位成功，不操作（由5s定时器上报）")
            return
        end
        if find_reporting then return end
        find_reporting = true
        log.info("active_mode", "寻宠30s定时器：GPS未定位成功，上报LBS保底")
        sys.taskInit(function()
            local ok, err = pcall(collect_data_and_report)
            find_reporting = false
            if not ok then log.error("active_mode", "寻宠30s上报异常:", err) end
        end)
    end

    -- 订阅 GPS 定位成功 / 丢失事件（驱动寻宠模式上报节奏）
    sys.subscribe("LOCATION_SUCCESS", find_on_gps_success)
    -- GNSS_STATE 事件（location.gnss_state_callback 处理后再分发到这里）：
    -- FIXED → 启动/重启 5s 高频（与 LOCATION_SUCCESS 双保险）；LOSE → 停止 5s 高频
    sys.subscribe("GNSS_STATE", function(event)
        if event == "FIXED" then
            find_on_gps_success()
        elseif event == "LOSE" then
            find_on_gps_lose()
        end
    end)

    -- 启动 30s LBS 保底循环定时器（5s 高频由 GPS 定位成功事件触发启动）
    sys.timerLoopStart(find_timer_30s, 30000)

    -- 寻宠模式：开机立即打开 GPS 常开（不等第一次 30s 检测）。
    -- GPS 后台持续定位，定位成功后由 GPS 定位成功事件驱动 5s 高频上报
    if get_work_mode() == config.DEVICE_MODE.FIND then
        location.start_find_gps()
    end

    log.info("active_mode", "寻宠模式GPS事件驱动已启用：定位成功→5s高频，未成功→30s LBS保底")
    -- ==============================================================

    while true do
        -- 寻宠模式：上报由 5s/30s 双循环定时器驱动，主循环只等待，不重复上报
        local work_mode = get_work_mode()
        local interval = last_calc_interval
        if work_mode == config.DEVICE_MODE.FIND then
            sys.wait(1000)
        else
            collect_data_and_report()

            -- 本次上报间隔已在 collect_data_and_report 中计算并存入 last_calc_interval
            interval = last_calc_interval
            log.info("active_mode", "等待下一次上报，间隔:", interval, "秒")
        end

        -- 非 GPS定位模式：上报完成后进入低功耗省电
        if work_mode ~= config.DEVICE_MODE.FIND then
            lowpower.set_mode_by_device_mode(work_mode)
        end

        -- 等待下一次上报触发：
        --   智能模式：等待 MOTION_EVENT（震动唤醒立即上报）或定时到点
        --   寻宠模式：GPS定位成功→5s高频上报；GPS未成功→30s LBS保底上报
        --   其他模式：等待 FORCE_REPORT（服务端指令）或定时到点
        local motion_wake = false
        if work_mode == config.DEVICE_MODE.SMART then
            motion_wake = sys.waitUntil(MOTION_EVENT, interval * 1000)
            if not motion_wake then
                motion_wake = false
            end
            -- 震动立即上报后进入冷却期（防抖），冷却期内震动不触发立即上报
            if motion_wake and in_motion_cooldown() then
                log.info("active_mode", "震动但处于冷却期内，忽略立即上报，等待冷却期结束（叠加计数不变）")
                motion_wake = false
                while in_motion_cooldown() do
                    sys.waitUntil(MOTION_EVENT, 1000)
                end
            end
        elseif work_mode == config.DEVICE_MODE.FIND then
            -- 寻宠模式主循环只等待（定时器驱动上报），不进低功耗以保持 GPS 常开
            sys.wait(1000)
        else
            sys.waitUntil("FORCE_REPORT", interval * 1000)
        end

        -- 震动唤醒：进入冷却期（震动不清零静止叠加计数，方案B）
        if motion_wake then
            log.info("active_mode", "震动事件唤醒，立即触发上报 + 进入冷却期（叠加计数不变）")
            -- 强制下一次上报走 GPS：即使 is_moving 因超时已恢复静止，震动触发也要精确定位
            force_gps_next_report = true
            cooldown_until = os.time() + get_motion_cooldown()
        end
    end
end

-- 启动已激活模式
log.info("active_mode", "启动已激活模式")
sys.taskInit(main_loop)
