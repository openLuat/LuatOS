--[[
@module  boot_lbs_report
@summary 开机联网后单独执行一次 LBS 定位并上报（独立运行，不与其他逻辑冲突）
@version 1.0
@date    2026.08.25
@usage
在 main.lua 启动云连接后调用 boot_lbs_report.start()：
1. 等待网络就绪（IP_READY）
2. 等待云平台连接成功（CLOUD_CONNECTED）
3. 执行一次 LBS 定位（lbsLoc2/AirLBS）
4. 通过 JSON 通道 + AirCloud TLV 双通道上报
5. 只运行一次即结束，不参与主循环、不影响上报频率
]]

local boot_lbs_report = {}

local config = require("config")

-- LBS 定位状态码（与 location.lua 的 get_lbs_status 一致）
-- 4=免费基站(lbsLoc2), 5=付费基站(AirLBS)
local function get_lbs_status()
    local mode = (config.AIRLBS_CONFIG and config.AIRLBS_CONFIG.MODE) or 0
    return mode == 1 and 5 or 4
end

-- 构建消息框架（JSON 通道）
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

-- 构建 AirCloud TLV 字段数组（与 active_mode.build_aircloud_tlv 一致）
-- 字符串字段非空才上报，避免空串编码失败
local function build_aircloud_tlv(d)
    local excloud = require("excloud")
    local FM = excloud.FIELD_MEANINGS
    local DT = excloud.DATA_TYPES
    local data = {}

    table.insert(data, { field_meaning = 1290, data_type = DT.INTEGER, value = d.work_mode or 0 })          -- 工作模式
    table.insert(data, { field_meaning = FM.VOLTAGE, data_type = DT.INTEGER, value = d.vbat or 0 })         -- 电池电压(mV)
    table.insert(data, { field_meaning = 1291, data_type = DT.INTEGER, value = d.bat_change or 0 })         -- 充电状态
    local signal = d.signal or 0
    table.insert(data, { field_meaning = FM.SIGNAL_STRENGTH_4G, data_type = DT.INTEGER, value = (signal > 0 and signal) or 0 })

    -- 位置：解析 "lat,lng" 为经度/纬度分开上报（512=经度 513=纬度，ASCII）
    if d.gps and d.gps ~= "" then
        local lat, lng = d.gps:match("^([%d%.%-]+),([%d%.%-]+)$")
        if lat and lng then
            table.insert(data, { field_meaning = FM.GNSS_LONGITUDE, data_type = DT.ASCII, value = tostring(lng) })
            table.insert(data, { field_meaning = FM.GNSS_LATITUDE, data_type = DT.ASCII, value = tostring(lat) })
        end
    end
    table.insert(data, { field_meaning = FM.LOCATION_METHOD, data_type = DT.ASCII, value = tostring(d.gps_status or 0) })

    if d.chip_model and d.chip_model ~= "" then
        table.insert(data, { field_meaning = FM.COMPONENT_MODEL, data_type = DT.ASCII, value = d.chip_model })
    end
    table.insert(data, { field_meaning = FM.WAKE_INTERVAL, data_type = DT.INTEGER, value = d.wake_interval or 0 })
    if d.iccid and d.iccid ~= "" then
        table.insert(data, { field_meaning = FM.SIM_ICCID, data_type = DT.ASCII, value = d.iccid })
    end

    return data
end

-- 执行一次 LBS 定位并双通道上报
local function do_lbs_report()
    local create = require("create")

    -- 1. 等待网络就绪（最多60秒）
    local net_timeout = 0
    while not socket.adapter(socket.dft()) do
        sys.waitUntil("IP_READY", 1000)
        net_timeout = net_timeout + 1
        if net_timeout >= 60 then
            log.warn("boot_lbs_report", "等待网络超时，放弃本次 LBS 上报")
            return
        end
    end
    log.info("boot_lbs_report", "网络已就绪")

    -- 2. 等待云平台连接成功（最多60秒）
    sys.waitUntil("CLOUD_CONNECTED", 60000)
    log.info("boot_lbs_report", "云平台已连接")

    -- 3. 执行一次 LBS 定位（lbsLoc2/AirLBS，独立于 GPS）
    local location = require("location")
    local lbs_data = location.get_lbs_location()
    if not lbs_data then
        log.warn("boot_lbs_report", "LBS 定位失败，跳过本次上报")
        return
    end

    local gps_status = get_lbs_status()
    local gps_str = string.format("%.5f,%.5f", lbs_data.lat, lbs_data.lng)
    log.info("boot_lbs_report", "LBS定位成功:", gps_str, "状态码:", gps_status)

    -- 4. 组装上报数据
    local battery = require("battery")
    local battery_data = battery.get_data()
    local kvstore = require("kvstore")
    local work_mode = kvstore.get_work_mode() or 0

    local d = {
        work_mode = work_mode,
        vbat = (battery_data and battery_data.voltage) or 0,
        bat_change = (battery_data and battery_data.charging and 1) or 0,
        signal = mobile.rsrp() or 0,
        gps = gps_str,
        gps_status = gps_status,
        iccid = mobile.iccid(),
        chip_model = "Air8202",
        wake_interval = 0,
    }

    -- 5. JSON 通道上报
    local msg = build_msg("boot_lbs_report")
    msg.data = d
    create.send(json.encode(msg))
    log.info("boot_lbs_report", "JSON 通道上报完成")

    -- 6. AirCloud TLV 通道上报
    create.send_aircloud(build_aircloud_tlv(d))
    log.info("boot_lbs_report", "AirCloud TLV 通道上报完成")

    -- 7. 发布完成事件（供其他模块监听，可选）
    sys.publish("BOOT_LBS_REPORT_DONE")
end

-- 启动开机 LBS 上报（独立任务，不阻塞主流程）
function boot_lbs_report.start()
    log.info("boot_lbs_report", "启动开机 LBS 定位上报任务")
    sys.taskInit(do_lbs_report)
end

return boot_lbs_report
