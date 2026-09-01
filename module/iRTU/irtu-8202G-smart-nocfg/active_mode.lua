--[[
@module active_mode
@summary 已激活模式（通过 create.lua 通道上报）
@version 4.2
@date    2026.09.02
@usage
已激活模式（004.000.009 起由 GNSS 开关策略驱动，不再按 work_mode 区分上报节奏）：
- 三个上报模式并存：实时上报 / GNSS 开启 / GNSS 关闭
- GNSS 开启条件（满足任一）：开机后 300 秒内；gsensor 正在震动；当前未震动但最近 180 秒内震过；
  实时上报模式结束后 180 秒内（强制进入 GNSS 开启模式）
- 实时上报（fast_report 下行命令触发）：每 1 秒上报一次，除 1293/1294 外其余 TLV 都上报，
  持续 1 分钟，期间暂停 GNSS 开关评估；进入时必须开启 GNSS（若未开立即强制开）；
  重复收到命令重置倒计时；结束强制进入 GNSS 开启模式
- GNSS 开：每 10 秒上报一次，功耗 mode0（全功率）
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

-- 本次上报的上报间隔（秒），供 779(wake_interval) 上报：GNSS 开→10 秒，GNSS 关→300 秒
local last_calc_interval = 0

-- ====== GNSS 开关策略（004.000.009 重构） ======
-- GNSS 开启条件（满足任一即开，全部不成立则关）：
--   1) 开机后 300 秒内
--   2) gsensor 正在震动
--   3) 当前未震动，但最近 180 秒内有过震动
-- 上报节奏：GNSS 开→每 10 秒上报一次（功耗 mode0）；GNSS 关→每 300 秒上报一次（功耗 mode1）

-- 震动事件名（gsensor 震动回调发布，主循环 waitUntil 监听，用于提前唤醒重新评估 GNSS 状态）
local MOTION_EVENT = "MOTION_EVENT"

local GNSS_BOOT_WINDOW = 300   -- 条件1：开机后 GNSS 常开时长（秒）
local GNSS_MOTION_KEEP = 180   -- 条件2/3：震动后 GNSS 保持开启的时长（秒）
local REPORT_GNSS_ON  = 10     -- GNSS 开启期间上报间隔（秒）
local REPORT_GNSS_OFF = 300    -- GNSS 关闭期间上报间隔（秒）

-- ====== 实时上报模式（fast_report，004.000.028 新增） ======
-- 服务器下发 fast_report 命令后进入：每秒上报一次，除 1293/1294 外其余 TLV 都上报，
-- 持续 FAST_REPORT_DURATION 秒后结束；进行中重复收到命令重置倒计时（续期）；
-- 结束后强制进入 GNSS 开启模式，并在 FAST_REPORT_GNSS_HOLD 秒内视为需要 GNSS
-- （之后恢复按 gsensor 条件正常评估）。
local FAST_REPORT_DURATION = 60    -- 实时上报持续时长（秒）= 1 分钟（每秒 1 次约 60 次上报）
local REPORT_FAST = 1              -- 实时上报期间上报间隔（秒）
local FAST_REPORT_GNSS_HOLD = 180  -- 实时上报结束后 GNSS 强制保持开启时长（秒）

local boot_ticks = 0           -- 主循环启动时的 mcu.ticks()（开机窗口基准，毫秒级不受 NTP 校时影响）
local gnss_active = false      -- GNSS 当前开关状态
local last_report_time = 0     -- 上次上报时间戳（上报节流）
local fast_report_active = false  -- 是否处于实时上报模式
local fast_report_deadline = 0    -- 实时上报模式结束时间戳（os.time，秒）
local fast_report_hold_until = 0  -- 实时上报结束后 GNSS 强制开启保持窗口截止时间戳

-- 评估当前是否需要开启 GNSS
local function is_gnss_required()
    -- 条件0：实时上报模式结束后 GNSS 强制保持窗口内（先进入 GNSS 开启模式，再按 gsensor 条件评估）
    if fast_report_hold_until > 0 and os.time() < fast_report_hold_until then
        return true
    end
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

-- 执行 GNSS 开启动作（三处复用：实时上报进入 / 实时上报结束强制 / 主循环按条件评估命中）
-- reason 为触发原因，写入日志与运维日志便于远程排查
local function switch_gnss_on(reason)
    gnss_active = true
    location.start_find_gps()                       -- 打开 GNSS（DEFAULT 常开应用）
    lowpower.set_mode(config.POWER_MODE.NORMAL)     -- 功耗 mode0（GNSS 需全功率）
    gsensor.stream_start()                          -- 开启 20Hz 三轴流式采样（TLV 1293 数据源）
    location.nmea_stream_start()                    -- 开启 1Hz NMEA 采样（TLV 1294 数据源）
    last_report_time = 0                            -- 立即触发一次上报
    tools.led_gnss_switched_on()                    -- LED 亮 10 秒（关→开切换提示）
    log.info("active_mode", "GNSS 开启（" .. reason .. "），功耗 mode0，每 10 秒上报")
    excloud.mtn_log("info", "gnss", "GNSS开启", "触发", reason, "上报间隔", REPORT_GNSS_ON .. "s")
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
-- xyz_stream：GNSS 开启期间 20Hz 流式采样的三轴原始数据（二进制，仅走 TLV 通道）
-- nmea_stream：GNSS 开启期间 1Hz 采样的定位五元组数据流（二进制，仅走 TLV 通道）
-- gnss_active：GNSS 是否开启；开启且非实时上报时不上报 1292（单点三轴），缩短整包报文长度
-- fast_report_active（模块级）：实时上报模式下 1292 单点三轴照常上报（此时 1293/1294 流不带）
local function build_aircloud_tlv(d, xyz_stream, nmea_stream, gnss_active)
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
    -- 上报条件：GNSS 关闭时（开启期间整包已带 1293 三轴原始流，单点三轴冗余，不上报以缩短报文），
    -- 或实时上报模式下（1293/1294 流不上报，单点三轴作为 gsensor 状态随每秒报文上报）
    if (not gnss_active or fast_report_active)
        and d.gsensor_xyz and d.gsensor_xyz ~= "" then
        table.insert(data, { field_meaning = 1292, data_type = DT.ASCII, value = d.gsensor_xyz })
    end
    -- DA221 20Hz 三轴原始数据流（仅 GNSS 开启期间采集）：最近 10 秒 200 个样本，
    -- 12bit 紧凑编码：每 2 样本 6 个 12bit 值拼 9 字节大端位流（bit 顺序 x1,y1,z1,x2,y2,z2），
    -- 200 样本 = 100 组 × 9 字节 = 900 字节，二进制字段，自定义编号 1293。
    -- 注意：二进制只走本 TLV 通道，不进 JSON 报文。
    if xyz_stream and xyz_stream ~= "" then
        table.insert(data, { field_meaning = 1293, data_type = DT.BINARY, value = xyz_stream })
    end
    -- GNSS 1Hz 定位五元组数据流（仅 GNSS 开启期间采集）：最近 10 个有效样本（10 秒），
    -- 每样本 10 字节 = 经度差/纬度差/速度/航向/海拔 各 2 字节有符号 int16 大端，时间正序，
    -- 共 100 字节，二进制字段，自定义编号 1294。
    -- 编码约定：经纬度为相对本报文 512/513 坐标的差值 ×100000（1LSB≈1.1m，范围±0.33°）；
    -- 速度 0.1km/h/LSB（RMC 节值×1.852）；航向 0.1°/LSB；海拔 1m/LSB。
    -- 注意：二进制只走本 TLV 通道，不进 JSON 报文。
    if nmea_stream and nmea_stream ~= "" then
        table.insert(data, { field_meaning = 1294, data_type = DT.BINARY, value = nmea_stream })
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
    -- 格式化为 "x,y,z" 逗号分隔字符串；JSON 报文始终携带，
    -- TLV 1292 字段：GNSS 关闭或实时上报模式下上报（开启且非实时上报时由 1293 原始流替代，见 build_aircloud_tlv）
    local x_acc, y_acc, z_acc = gsensor.read_xyz()
    local gsensor_xyz = ""
    if x_acc then
        gsensor_xyz = string.format("%.3f,%.3f,%.3f", x_acc, y_acc, z_acc)
    else
        log.warn("active_mode", "gsensor 未初始化，三轴数据不上报")
    end

    -- GNSS 开启且非实时上报期间：取 20Hz 流式采样的最近 200 个样本
    -- （10 秒 × 20Hz，12bit 紧凑编码 = 100 组 × 9 字节 = 900 字节），作为 TLV 1293 二进制字段
    -- 随本次报文上报。注意：二进制数据只走 AirCloud TLV 通道，不进 JSON 报文（避免 json.encode
    -- 产生非法 JSON）；采样由 gsensor 常驻任务后台进行，本协程阻塞（等网络/发数据）期间采样不中断。
    -- 实时上报模式下不上报 1293（用户要求每秒报文只带常规字段），故不取流也不判异常。
    local gsensor_stream, stream_count = "", 0
    if gnss_active and not fast_report_active then
        gsensor_stream, stream_count = gsensor.get_stream_data(200)
        if stream_count > 0 then
            log.info("active_mode", "gsensor_stream:", stream_count, "样本", #gsensor_stream, "字节")
        else
            log.info("active_mode", "gsensor_stream: 无数据（刚开启采样，本次报文不带 1293 字段）")
            -- GNSS 开启期间 1293 流无样本属于采样异常（刚切换后首包除外），写入运维日志便于远程排查
            excloud.mtn_log("warn", "gsensor", "1293上报异常", "GNSS开启但流式采样0样本")
        end
    end

    -- 额外上报字段
    local gsv = get_gsv_report()
    local boot_reason = get_boot_reason()
    local cur_band = get_current_band()
    -- 驻留频段格式化为 "LTE B{n}"
    local band_str = cur_band and ("LTE B" .. cur_band) or ""
    -- 779(wake_interval)：上报本次实际使用的上报间隔（秒）
    -- 三态：实时上报→1 秒，GNSS 开→10 秒，GNSS 关→300 秒
    if fast_report_active then
        last_calc_interval = REPORT_FAST
    else
        last_calc_interval = gnss_active and REPORT_GNSS_ON or REPORT_GNSS_OFF
    end
    local wake_interval = last_calc_interval

    -- 构建属性上报消息
    local msg = build_msg("property_report")
    local gps_str = loc_data and loc_data.gps or ""
    local gps_status = loc_data and loc_data.gps_status or 0

    -- GNSS 开启且非实时上报期间：取 1Hz NMEA 采样的最近 10 个样本（10 秒 × 10 字节 = 100 字节），
    -- 作为 TLV 1294 二进制字段随本次报文上报。
    -- 经纬度以本次报文坐标（512/513 字段，即 loc_data.gps）为参考做差值编码，
    -- 服务端用报文经纬度 + 差值即可还原每秒的绝对坐标。
    -- 注意：二进制数据只走 AirCloud TLV 通道，不进 JSON 报文；
    -- 采样由 location 常驻任务后台进行，本协程阻塞（等网络/发数据）期间采样不中断。
    -- 实时上报模式下不上报 1294（与 1293 同理），故不取流。
    local nmea_stream_bin, nmea_count = "", 0
    if gnss_active and not fast_report_active then
        local ref_lat, ref_lng = nil, nil
        if gps_str ~= "" then
            local la, ln = gps_str:match("^([%d%.%-]+),([%d%.%-]+)$")
            if la and ln then ref_lat, ref_lng = tonumber(la), tonumber(ln) end
        end
        nmea_stream_bin, nmea_count = location.get_nmea_stream(ref_lat, ref_lng)
        if nmea_count > 0 then
            log.info("active_mode", "nmea_stream:", nmea_count, "样本", #nmea_stream_bin, "字节")
        else
            log.info("active_mode", "nmea_stream: 无数据（未定位成功，本次报文不带 1294 字段）")
        end
    end

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

    -- AirCloud 通道：以 TLV 形式上报（其余字段不含 msg_id/type/ts/imei；
    -- 1293 为 GNSS 开启期间的 20Hz 三轴原始数据流（12bit 紧凑编码），
    -- 1294 为 GNSS 开启期间的 1Hz 定位五元组数据流，均为二进制，仅走此通道；
    -- 1292 单点三轴：GNSS 关闭或实时上报模式下上报）
    create.send_aircloud(build_aircloud_tlv(msg.data, gsensor_stream, nmea_stream_bin, gnss_active))
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

    -- 订阅实时上报命令（remote.fast_report 发布）：无论当前 GNSS 开启/关闭，立即进入实时上报模式。
    -- 持续 FAST_REPORT_DURATION 秒后由主循环统一结束；进行中重复收到命令则重置倒计时（续期 1 分钟）。
    -- 进入实时上报模式必须开启 GNSS（实时上报要带实时位置），若当前关闭则立即执行开启动作；
    -- 实时上报期间主循环暂停 GNSS 评估，不会与之冲突。
    sys.subscribe("FAST_REPORT_START", function()
        if not gnss_active then
            switch_gnss_on("fast_report进入实时上报强制")
        end
        fast_report_active = true
        fast_report_deadline = os.time() + FAST_REPORT_DURATION
        log.info("active_mode", "收到 fast_report：进入实时上报模式，每", REPORT_FAST,
            "秒上报（不带1293/1294），持续", FAST_REPORT_DURATION, "秒")
        excloud.mtn_log("info", "fast_report", "进入实时上报模式",
            "持续", FAST_REPORT_DURATION .. "s", "间隔", REPORT_FAST .. "s")
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

    log.info("active_mode", "上报模式：实时上报(1s,fast_report) / GNSS开(10s) / GNSS关(300s)，实时上报结束强制进GNSS开")

    while true do
        -- 0) 实时上报模式到期检查：持续 FAST_REPORT_DURATION 秒后结束，
        --    结束后必须先进入 GNSS 开启模式（若当前未开则强制打开，并给一个保持窗口），
        --    之后由 is_gnss_required 按 gsensor 条件正常评估进入其他模式
        if fast_report_active and os.time() >= fast_report_deadline then
            fast_report_active = false
            fast_report_hold_until = os.time() + FAST_REPORT_GNSS_HOLD
            log.info("active_mode", "实时上报模式结束（已持续", FAST_REPORT_DURATION, "秒），强制进入 GNSS 开启模式")
            excloud.mtn_log("info", "fast_report", "实时上报模式结束", "强制进入GNSS开启模式")
            if not gnss_active then
                switch_gnss_on("实时上报结束强制")
            end
        end

        -- 1) 评估 GNSS 开关需求（开机窗口 / 正在震动 / 180 秒内震过 / 实时上报结束保持窗口）
        --    实时上报模式期间暂停评估（期间不切换 GNSS 开关，结束后统一处理）
        if not fast_report_active then
            local gnss_needed = is_gnss_required()

            -- 2) GNSS 状态机：仅在状态切换时执行开关动作
            if gnss_needed and not gnss_active then
                switch_gnss_on("开机窗口/震动")
            elseif not gnss_needed and gnss_active then
                gnss_active = false
                location.stop_find_gps()                        -- 关闭 GNSS
                lowpower.set_mode(config.POWER_MODE.POWER_SAVE) -- 功耗 mode1（低功耗）
                gsensor.stream_stop()                           -- 停止 20Hz 流式采样并清空缓冲
                location.nmea_stream_stop()                     -- 停止 1Hz NMEA 采样并清空缓冲
                log.info("active_mode", "GNSS 关闭（无震动超时），功耗 mode1，每 300 秒上报")
                excloud.mtn_log("info", "gnss", "GNSS关闭", "触发", "无震动超时", "上报间隔", REPORT_GNSS_OFF .. "s")
            end
        end

        -- 3) 上报节流：实时上报→1 秒一次；GNSS 开→10 秒一次；GNSS 关→300 秒一次
        local interval = REPORT_GNSS_ON
        if fast_report_active then
            interval = REPORT_FAST
        elseif not gnss_active then
            interval = REPORT_GNSS_OFF
        end
        if os.time() - last_report_time >= interval then
            local ok, err = pcall(collect_data_and_report)
            if not ok then
                log.error("active_mode", "上报异常:", err)
            end
            last_report_time = os.time()

            -- GNSS 关闭且非实时上报期间：上报内部会临时切全功率，上报完恢复功耗 mode1
            -- （实时上报模式每秒上报一次，且结束后会强制进入 GNSS 开启，保持 mode0 避免功耗模式震荡）
            if not gnss_active and not fast_report_active then
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
