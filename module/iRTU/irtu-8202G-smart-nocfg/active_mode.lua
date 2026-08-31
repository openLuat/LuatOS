--[[
@module active_mode
@summary 已激活模式（通过 create.lua 通道上报）
@version 4.0
@date    2026.08.28
@usage
已激活模式（004.000.009 起由 GNSS 开关策略驱动，不再按 work_mode 区分上报节奏）：
- GNSS 开启条件（满足任一）：开机后 300 秒内；gsensor 正在震动；当前未震动但最近 30 秒内震过
- GNSS 开：每 5 秒上报一次，功耗 mode0（全功率）
- GNSS 关：每 300 秒上报一次，功耗 mode1（低功耗）
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

-- 本次上报的上报间隔（秒），供 779(wake_interval) 上报：GNSS 开→5 秒，GNSS 关→300 秒
local last_calc_interval = 0

-- ====== GNSS 开关策略（004.000.009 重构） ======
-- GNSS 开启条件（满足任一即开，全部不成立则关）：
--   1) 开机后 300 秒内
--   2) gsensor 正在震动
--   3) 当前未震动，但最近 30 秒内有过震动
-- 上报节奏：GNSS 开→每 5 秒上报一次（功耗 mode0）；GNSS 关→每 300 秒上报一次（功耗 mode1）

-- 震动事件名（gsensor 震动回调发布，主循环 waitUntil 监听，用于提前唤醒重新评估 GNSS 状态）
local MOTION_EVENT = "MOTION_EVENT"

local GNSS_BOOT_WINDOW = 300   -- 条件1：开机后 GNSS 常开时长（秒）
local GNSS_MOTION_KEEP = 180   -- 条件2/3：震动后 GNSS 保持开启的时长（秒）
local REPORT_GNSS_ON  = 5      -- GNSS 开启期间上报间隔（秒）
local REPORT_GNSS_OFF = 300    -- GNSS 关闭期间上报间隔（秒）

local boot_ticks = 0           -- 主循环启动时的 mcu.ticks()（开机窗口基准，毫秒级不受 NTP 校时影响）
local gnss_active = false      -- GNSS 当前开关状态
local last_report_time = 0     -- 上次上报时间戳（上报节流）

-- 评估当前是否需要开启 GNSS
local function is_gnss_required()
    -- 条件1：开机 300 秒内（mcu.ticks 返回毫秒 tick）
    if (mcu.ticks() - boot_ticks) / 1000 < GNSS_BOOT_WINDOW then
        return true
    end
    -- 条件2+3：正在震动，或最近 180 秒内有过震动
    -- （last_motion_time 每次震动都会刷新，以 180 秒窗口统一判定，同时涵盖两种情况）
    local st = gsensor.get_status()
    if st and st.last_motion_time and st.last_motion_time > 0
        and (os.time() - st.last_motion_time) <= GNSS_MOTION_KEEP then
        return true
    end
    return false
end
-- ================================================

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
    -- DA221 三轴加速度：格式 "x,y,z"（单位 g，3位小数），自定义编号 1292
    if d.gsensor_xyz and d.gsensor_xyz ~= "" then
        table.insert(data, { field_meaning = 1292, data_type = DT.ASCII, value = d.gsensor_xyz })
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

    -- LED 已由 tools.lua 状态机自动控制（开机60s / GNSS切换10s / 充电常亮；
    -- 通信正常常亮，否则闪烁；充电红 / 充满绿），此处不再手动控灯

    -- 低电量检测
    local is_low_power = false
    local battery_data = battery.force_check()
    if battery_data and battery_data.level then
        is_low_power = battery_data.level < config.ALARM_THRESHOLD.BATTERY_CRITICAL
        kvstore.set_low_power_mode(is_low_power)
    end

    -- 定位采集（GNSS 优先锁定策略）：
    -- 开机以来 GNSS 定位成功过一次 → 永远用 GNSS 数据（当前成功用当前值，否则用最近一次成功值），gps_status 恒 2，不再用 LBS
    -- 从未成功 → 走 LBS（gps_status 为 4/5，失败 3）
    local loc_data = location.get_report_location(gnss_active)

    -- 信号强度（CSQ，范围 0-31，值越大信号越好；99=无信号）
    local signal = mobile.csq() or 0

    -- DA221 三轴加速度（单位 g，协程上下文可直接读 I2C）
    -- 格式化为 "x,y,z" 逗号分隔字符串，作为 TLV 1292 的 V 字段上报
    local x_acc, y_acc, z_acc = gsensor.read_xyz()
    local gsensor_xyz = ""
    if x_acc then
        gsensor_xyz = string.format("%.3f,%.3f,%.3f", x_acc, y_acc, z_acc)
    else
        log.warn("active_mode", "gsensor 未初始化，三轴数据不上报")
    end

    -- 额外上报字段
    local gsv = get_gsv_report()
    local boot_reason = get_boot_reason()
    local cur_band = get_current_band()
    -- 驻留频段格式化为 "LTE B{n}"
    local band_str = cur_band and ("LTE B" .. cur_band) or ""
    -- 779(wake_interval)：上报本次实际使用的上报间隔（秒）
    -- 由 GNSS 开关状态决定：开→5 秒，关→300 秒（不再按模式/服务端配置计算）
    last_calc_interval = gnss_active and REPORT_GNSS_ON or REPORT_GNSS_OFF
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
        sat_visible = gsv.sat_visible,
        gsensor_xyz = gsensor_xyz
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
    log.info("active_mode", "gsensor_xyz:", msg.data.gsensor_xyz ~= "" and msg.data.gsensor_xyz or "nil")
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
    -- 主循环收到后重新评估 GNSS 开关状态（震动→开 GNSS→立即上报）
    gsensor.on_vibration(function()
        log.info("active_mode", "检测到震动，发布 MOTION_EVENT")
        sys.publish(MOTION_EVENT)
    end, 2000)

    -- 常驻订阅震动事件置标志：上报阻塞期间（网络等待最长30秒）发布的 MOTION_EVENT
    -- 无人 waitUntil 会丢失，用标志兜底，等待前先查标志
    local motion_event_flag = false
    sys.subscribe(MOTION_EVENT, function()
        motion_event_flag = true
    end)

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

    -- 开机窗口基准：开机 300 秒内 GNSS 常开（mcu.ticks 为毫秒级 tick，不受 NTP 校时影响）
    boot_ticks = mcu.ticks()
    last_report_time = 0

    log.info("active_mode", "GNSS 开关策略已启用：开机300s/震动30s内→GNSS开+5s上报，否则→GNSS关+300s上报+mode1")

    while true do
        -- 1) 评估 GNSS 开关需求（开机窗口 / 正在震动 / 30 秒内震过）
        local gnss_needed = is_gnss_required()

        -- 2) GNSS 状态机：仅在状态切换时执行开关动作
        if gnss_needed and not gnss_active then
            gnss_active = true
            location.start_find_gps()                       -- 打开 GNSS（DEFAULT 常开应用）
            lowpower.set_mode(config.POWER_MODE.NORMAL)     -- 功耗 mode0（GNSS 需全功率）
            last_report_time = 0                            -- 立即触发一次上报
            tools.led_gnss_switched_on()                    -- LED 亮 10 秒（关→开切换提示）
            log.info("active_mode", "GNSS 开启（开机窗口/震动），功耗 mode0，每 5 秒上报")
        elseif not gnss_needed and gnss_active then
            gnss_active = false
            location.stop_find_gps()                        -- 关闭 GNSS
            lowpower.set_mode(config.POWER_MODE.POWER_SAVE) -- 功耗 mode1（低功耗）
            log.info("active_mode", "GNSS 关闭（无震动超时），功耗 mode1，每 300 秒上报")
        end

        -- 3) 上报节流：GNSS 开→5 秒一次；GNSS 关→300 秒一次
        local interval = gnss_active and REPORT_GNSS_ON or REPORT_GNSS_OFF
        if os.time() - last_report_time >= interval then
            local ok, err = pcall(collect_data_and_report)
            if not ok then
                log.error("active_mode", "上报异常:", err)
            end
            last_report_time = os.time()

            -- GNSS 关闭期间：上报内部会临时切全功率，上报完恢复功耗 mode1
            if not gnss_active then
                lowpower.set_mode(config.POWER_MODE.POWER_SAVE)
            end
        end

        -- 4) 等待：震动事件（含上报阻塞期间丢失的）立即进入下一轮评估；否则等到下一上报周期
        if not motion_event_flag then
            local remain = interval - (os.time() - last_report_time)
            if remain < 1 then remain = 1 end
            sys.waitUntil(MOTION_EVENT, remain * 1000)
        end
        motion_event_flag = false
    end
end

-- 启动已激活模式
log.info("active_mode", "启动已激活模式")
sys.taskInit(main_loop)
