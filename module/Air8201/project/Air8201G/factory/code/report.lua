--[[
@module  report
@summary 数据上报模块
@version 1.1
@date    2026.05.27
@description
    实现定时数据上报功能，包括位置、电池、系统状态等信息的上报
    本版本已移除 config 依赖与 fskv 写入，上报间隔/包计数/重启计数全部内存化。
]]

local report = {}

-- 导入模块
local excloud = require "excloud"
local excloud_module = require "excloud_module"
local mygps = require "mygps"
local mypower = require "mypower"
local gsensor = require "gsensor"
local global_config = require "global_config"

-- ========== 硬编码常量（原 config 默认值） ==========
local REPORT_INTERVAL          = 300000       -- 兼容旧接口：固定上报间隔(毫秒)
local REPORT_INTERVAL_MOVING   = 300000       -- 运动中上报间隔(毫秒)：5min（统一）
local REPORT_INTERVAL_STATIC   = 300000       -- 静止中上报间隔(毫秒)：5min（统一）
local MOTION_REPORT_COOLDOWN   = 600000       -- 震动上报冷却期(毫秒)：10min（冷却期内震动不再触发上报）
local GNSS_REQUEST_INTERVAL    = 1800000      -- GNSS 触发间隔(毫秒)：30min/次（独立于定时上报间隔）
local COMPONENT_MODEL_FALLBACK = "Air8201G"   -- 元器件型号兜底值

-- ========== 上报原因枚举（写入 RANDOM_DATA 字段，ASCII 类型） ==========
local REPORT_REASON = {
    TIMER       = "TIMER",       -- 定时上报
    MOTION      = "MOTION",      -- Gsensor 震动触发上报
    PWRKEY      = "PWRKEY",      -- 开机首次上报（设备上电后第一次状态上报）
    MANUAL      = "MANUAL",      -- 手动/远程触发上报
    GPS_TRIGGER = "GPS_TRIGGER", -- WAKEUP0 中断触发：强制 GNSS 定位 + 立即上报一次
}
-- ====================================================

-- 智能上报开关：保留兼容，但已无意义（间隔已统一为 5min）
local SMART_INTERVAL_ENABLED   = false

-- 震动冷却期状态（仅内存，无持久化）
local last_motion_report_sec   = 0  -- 上次震动触发上报的时间戳(秒，os.time)

-- GNSS 上次触发时间戳（毫秒）
local last_gnss_trigger_sec    = 0  -- 上次触发 GNSS 定位的时间戳(秒)，0=从未触发

-- 定时器
local report_timer = nil
local report_interval = REPORT_INTERVAL

-- 当前上报原因（每次进入 report_task 前由调度方设置）
local current_report_reason = REPORT_REASON.TIMER

-- 业务上报 SN（仅统计 4 类业务上报：PWRKEY/TIMER/MOTION/MANUAL，每次成功+1）
-- 命名兼容旧接口 packet_count，但语义已严格收敛
local packet_count = 0

-- 首次开机时间戳（秒，os.time）：用于在线时间字段计算
-- 在 report.start() 中初始化为 os.time()
local boot_time_sec = 0

-- 重启次数（仅内存，无持久化，每次开机从 0 开始）
local reboot_count = 0

-- 获取重启原因（返回字符串）
-- 依据：合宙官方所有模组（Air780EPM/EHM/Air8000/Air8101/Air1601/Air8201 等）都支持 pm.lastReson()
--      参考 https://gitee.com/openLuat/LuatOS/blob/master/module/Air780EPM/demo/wdt/internal_wdt.lua
-- pm.lastReson() 返回 3 个值（reason1, reason2, reason3），全部上报，便于云端分析。
-- 返回值格式：字符串 "<r1>,<r2>,<r3>"（如 "0,0,0" 表示正常上电；"1,0,0" 表示看门狗复位）
local function get_reboot_reason()
    -- 所有合宙模组都支持此接口，无需 pcall 保护
    local r1, r2, r3 = pm.lastReson()

    -- 将 nil 转 "0"，保证字符串始终有 3 个段
    local s1 = tostring(r1 or 0)
    local s2 = tostring(r2 or 0)
    local s3 = tostring(r3 or 0)
    local reason_str = s1 .. "," .. s2 .. "," .. s3

    log.info("REPORT", "重启原因 pm.lastReson() ->",
                       "r1=" .. s1, "r2=" .. s2, "r3=" .. s3,
                       "上报字符串=" .. reason_str)
    return reason_str
end

-- 获取系统信息
local function get_system_info()
    -- CPU温度
    adc.open(adc.CH_CPU)
    local cpu_temp = adc.get(adc.CH_CPU)

    -- 信号强度
    local signal = 0
    if mobile.csq then
        local csq = mobile.csq()
        if csq then signal = tonumber(csq) or 0 end
    elseif mobile.rssi then
        local rssi_result = mobile.rssi()
        if rssi_result then signal = tonumber(rssi_result) or 0 end
    elseif net and net.simSignalStrength then
        signal = tonumber(net.simSignalStrength()) or 0
    end

    log.info("REPORT", "信号强度:", signal)

    -- 驻留小区
    local cell_info = ""
    local serving_cell = 0
    local serving_cell_detail = nil

    if mobile and mobile.scell then
        serving_cell_detail = mobile.scell()
        if serving_cell_detail then
            log.info("REPORT", "scell成功:", json.encode(serving_cell_detail))
            serving_cell = serving_cell_detail.band or 0
            cell_info = string.format("%d,%d,%d,%d,%d,%d,%d,%d,%d,%d",
                serving_cell_detail.mcc or 0,
                serving_cell_detail.mnc or 0,
                serving_cell_detail.tac or 0,
                serving_cell_detail.cid or 0,
                serving_cell_detail.earfcn or 0,
                serving_cell_detail.pci or 0,
                serving_cell_detail.rsrp or 0,
                serving_cell_detail.rsrq or 0,
                serving_cell_detail.snr or 0,
                serving_cell_detail.rssi or 0
            )
        end
    end

    if serving_cell == 0 and mobile and mobile.getCellInfo and mobile.reqCellInfo then
        mobile.reqCellInfo(15)
        local cell_list = mobile.getCellInfo()
        if cell_list and #cell_list > 0 then
            log.info("REPORT", "getCellInfo成功")
            local serving = cell_list[1]
            if serving and serving.mcc and serving.mnc then
                cell_info = string.format("%d,%d,%d,%d,%d,%d,0,0,0,0",
                    serving.mcc or 0,
                    serving.mnc or 0,
                    serving.lac or 0,
                    serving.cid or 0,
                    serving.earfcn or 0,
                    serving.pci or 0
                )
            end
        end
    end

    if cell_info == "" and mobile and mobile.getNetInfo then
        local net_info = mobile.getNetInfo()
        if net_info then
            cell_info = string.format("%d,%d,%d,%d,0,0,0,0,0,0",
                net_info.mcc or 0,
                net_info.mnc or 0,
                net_info.lac or 0,
                net_info.cid or 0
            )
        end
    end

    if cell_info == "" and ntf and ntf.getInfo then
        local ntf_info = ntf.getInfo()
        if ntf_info and ntf_info.mcc and ntf_info.mnc then
            cell_info = string.format("%d,%d,%d,%d,0,0,0,0,0,0",
                ntf_info.mcc or 0,
                ntf_info.mnc or 0,
                ntf_info.lac or 0,
                ntf_info.cid or 0
            )
        end
    end

    if cell_info == "" and net and net.getInfo then
        local net_info_alt = net.getInfo()
        if net_info_alt and net_info_alt.mcc and net_info_alt.mnc then
            cell_info = string.format("%d,%d,%d,%d,0,0,0,0,0,0",
                net_info_alt.mcc or 0,
                net_info_alt.mnc or 0,
                net_info_alt.lac or 0,
                net_info_alt.cid or 0
            )
        end
    end

    log.info("REPORT", "cell_info:", cell_info, "serving_cell(band):", serving_cell)

    -- 元器件型号
    local component_model = COMPONENT_MODEL_FALLBACK
    if hmeta and hmeta.getPartNumber then
        component_model = hmeta.getPartNumber() or COMPONENT_MODEL_FALLBACK
    end

    -- 软件版本
    local firmware_version = ""
    if rtos and rtos.version then
        firmware_version = rtos.version()
    end

    -- 联网方式
    local network_type = 0
    if mobile and mobile.getNetInfo then
        local net_info = mobile.getNetInfo()
        if net_info and net_info.rat then
            local rat = net_info.rat
            if rat == 7 or rat == 8 then
                network_type = 1
            elseif rat == 2 or rat == 3 or rat == 6 then
                network_type = 2
            elseif rat == 1 or rat == 5 then
                network_type = 3
            end
        end
    end

    -- IP类型
    local network_ip_type = 0
    local ip = socket.localIP()
    if ip then
        if ip:find(":") then
            network_ip_type = 2
        elseif ip:find("%.") then
            network_ip_type = 1
        end
    end

    return {
        imei = mobile.imei(),
        iccid = mobile.iccid(),
        temperature = cpu_temp,
        reboot_reason = get_reboot_reason(),
        reboot_count = reboot_count,
        signal = signal,
        cell_info = cell_info,
        serving_cell = serving_cell,
        serving_cell_detail = serving_cell_detail,
        component_model = component_model,
        firmware_version = firmware_version,
        network_type = network_type,
        network_ip_type = network_ip_type,
        -- 休眠模式：动态读取 mypower 的低功耗常驻状态
        -- true → 1（普通低功耗，pm.power(pm.WORK_MODE, 1)）
        -- false → 0（全速运行，未进入低功耗）
        sleep_mode = mypower.is_lowpower_mode() and 1 or 0
    }
end

-- 上报状态信息
function report.send_status()
    log.info("REPORT", "发送状态上报")

    local system_info = get_system_info()
    local battery_level = mypower.get_battery_level()
    local battery_voltage = mypower.get_battery_voltage()
    local is_charging = mypower.is_charging()
    local location = mygps.get_location()
    local current_time = os.time()

    log.info("REPORT", "电池电量:", battery_level, "电压:", battery_voltage, "充电中:", is_charging)
    log.info("REPORT", "数据包计数:", packet_count)

    local data = {
        {
            field_meaning = excloud.FIELD_MEANINGS.SIGNAL_STRENGTH_4G,
            data_type = excloud.DATA_TYPES.INTEGER,
            value = system_info.signal or 0
        },
        {
            field_meaning = excloud.FIELD_MEANINGS.SIM_ICCID,
            data_type = excloud.DATA_TYPES.ASCII,
            value = system_info.iccid or ""
        },
        {
            field_meaning = excloud.FIELD_MEANINGS.BATTERY_LEVEL,
            data_type = excloud.DATA_TYPES.INTEGER,
            value = battery_level
        },
        {
            field_meaning = excloud.FIELD_MEANINGS.VOLTAGE,
            data_type = excloud.DATA_TYPES.INTEGER,
            value = math.floor((battery_voltage or 0) * 1000)
        },
        {
            field_meaning = excloud.FIELD_MEANINGS.DEVICE_ID,
            data_type = excloud.DATA_TYPES.ASCII,
            value = system_info.imei or ""
        },
        {
            field_meaning = excloud.FIELD_MEANINGS.COMPONENT_MODEL,
            data_type = excloud.DATA_TYPES.ASCII,
            value = system_info.component_model or COMPONENT_MODEL_FALLBACK
        },
        {
            field_meaning = excloud.FIELD_MEANINGS.CELL_INFO,
            data_type = excloud.DATA_TYPES.ASCII,
            value = system_info.cell_info or ""
        },
        {
            field_meaning = excloud.FIELD_MEANINGS.SERVING_CELL,
            data_type = excloud.DATA_TYPES.INTEGER,
            value = system_info.serving_cell or 0
        },
        {
            field_meaning = excloud.FIELD_MEANINGS.NETWORK_TYPE,
            data_type = excloud.DATA_TYPES.INTEGER,
            value = system_info.network_type or 0
        },
        {
            field_meaning = excloud.FIELD_MEANINGS.NETWORK_IP_TYPE,
            data_type = excloud.DATA_TYPES.INTEGER,
            value = system_info.network_ip_type or 0
        },
        {
            field_meaning = excloud.FIELD_MEANINGS.SLEEP_MODE,
            data_type = excloud.DATA_TYPES.INTEGER,
            value = system_info.sleep_mode or 0
        },
        {
            field_meaning = excloud.FIELD_MEANINGS.BOOT_REASON,
            data_type = excloud.DATA_TYPES.ASCII,
            value = system_info.reboot_reason or "0,0,0"
        },
        {
            field_meaning = excloud.FIELD_MEANINGS.BOOT_COUNT,
            data_type = excloud.DATA_TYPES.INTEGER,
            value = system_info.reboot_count
        },
        {
            field_meaning = excloud.FIELD_MEANINGS.ENV_TEMPERATURE,
            data_type = excloud.DATA_TYPES.FLOAT,
            value = (system_info.temperature or 0) / 1000
        },
        {
            field_meaning = excloud.FIELD_MEANINGS.FIRMWARE_VERSION,
            data_type = excloud.DATA_TYPES.ASCII,
            value = system_info.firmware_version or ""
        },
        {
            field_meaning = excloud.FIELD_MEANINGS.TIMESTAMP,
            data_type = excloud.DATA_TYPES.INTEGER,
            value = current_time
        },
        {
            -- 上报原因：复用 RANDOM_DATA(1281) 字段（语义"无意义数据"，专用于自定义业务标识）
            -- 取值见 REPORT_REASON：TIMER / MOTION / PWRKEY / MANUAL
            field_meaning = excloud.FIELD_MEANINGS.RANDOM_DATA,
            data_type = excloud.DATA_TYPES.ASCII,
            value = current_report_reason or REPORT_REASON.TIMER
        },
        {
            -- 业务上报 SN（本次包的业务流水号，连续递增，不含心跳/online 等系统包）
            -- 复用自定义字段编号 1282
            field_meaning = 1282,
            data_type = excloud.DATA_TYPES.INTEGER,
            value = packet_count + 1   -- 本次即将+1，先取下一个值上报
        },
        {
            -- 在线时间（分钟）：(本次上报时间 - 首次开机时间) / 60，累计总在线分钟数
            -- 复用自定义字段编号 1284
            field_meaning = 1284,
            data_type = excloud.DATA_TYPES.INTEGER,
            value = (boot_time_sec > 0) and math.floor((current_time - boot_time_sec) / 60) or 0
        },
        {
            -- 心跳总数（复用 gcfg_report_count，含业务 + 心跳总发送次数）
            field_meaning = 1285,
            data_type = excloud.DATA_TYPES.INTEGER,
            value = (function()
                local s = global_config.get_stats()
                return s.report_count
            end)()
        },
        {
            -- TCP 断联次数（已连接的 TCP 链路被断开）
            field_meaning = 1286,
            data_type = excloud.DATA_TYPES.INTEGER,
            value = (function()
                local s = global_config.get_stats()
                return s.tcp_drop_count
            end)()
        },
        {
            -- 断网次数（网络层断开事件）
            field_meaning = 1287,
            data_type = excloud.DATA_TYPES.INTEGER,
            value = (function()
                local s = global_config.get_stats()
                return s.disconnect_count
            end)()
        },
        {
            -- 重启次数（硬件 reset + 软件重启合计，不含冷启动）
            field_meaning = 1288,
            data_type = excloud.DATA_TYPES.INTEGER,
            value = (function()
                local s = global_config.get_stats()
                return s.reset_count
            end)()
        },
        {
            -- PWRKEY 上电时间（首次上电开机时间戳，秒）
            field_meaning = 1289,
            data_type = excloud.DATA_TYPES.INTEGER,
            value = (function()
                local s = global_config.get_stats()
                return s.boot_time
            end)()
        },
        {
            -- GNSS 定位结果：复用 GNSS_INFO(520) 字段（语义"GNSS芯片型号和固件版本号"，扩展为定位结果摘要）
            -- 取值格式：
            --   成功 -> "lat,lng"（如 "31.123456,121.654321"）
            --   失败 -> "0.000000,0.000000"（按业务要求：定位失败，经纬度为 0 也汇总上报）
            --   未触发 -> "SKIP"（本次上报不触发 GNSS，未尝试定位）
            field_meaning = excloud.FIELD_MEANINGS.GNSS_INFO,
            data_type = excloud.DATA_TYPES.ASCII,
            value = (function()
                local g = mygps.get_last_gnss_result()
                if not g or g.timestamp == 0 then
                    return "SKIP"
                end
                if g.ok then
                    return string.format("%.6f,%.6f", g.lat, g.lng)
                else
                    return "0.000000,0.000000"
                end
            end)()
        }
    }

    log.info("REPORT", "上报字段数量:", #data, "上报原因:", current_report_reason)

    -- 位置补充
    local has_valid_location = location and location.lat and location.lat ~= 0 and location.lng and location.lng ~= 0
    if has_valid_location then
        local location_source = location.source or "UNKNOWN"
        log.info("REPORT", "位置来源:", location_source, "经纬度:", location.lat, location.lng)

        table.insert(data, {
            field_meaning = excloud.FIELD_MEANINGS.GNSS_LATITUDE,
            data_type = excloud.DATA_TYPES.FLOAT,
            value = location.lat
        })
        table.insert(data, {
            field_meaning = excloud.FIELD_MEANINGS.GNSS_LONGITUDE,
            data_type = excloud.DATA_TYPES.FLOAT,
            value = location.lng
        })
        table.insert(data, {
            field_meaning = excloud.FIELD_MEANINGS.LOCATION_METHOD,
            data_type = excloud.DATA_TYPES.ASCII,
            value = location_source
        })

        if location_source == "GNSS" then
            table.insert(data, {
                field_meaning = excloud.FIELD_MEANINGS.SPEED,
                data_type = excloud.DATA_TYPES.FLOAT,
                value = location.speed or 0
            })
            table.insert(data, {
                field_meaning = excloud.FIELD_MEANINGS.HEADING,
                data_type = excloud.DATA_TYPES.FLOAT,
                value = location.heading or 0
            })
            table.insert(data, {
                field_meaning = excloud.FIELD_MEANINGS.ALTITUDE,
                data_type = excloud.DATA_TYPES.FLOAT,
                value = location.altitude or 0
            })
            table.insert(data, {
                field_meaning = excloud.FIELD_MEANINGS.SATELLITES_TOTAL,
                data_type = excloud.DATA_TYPES.INTEGER,
                value = location.satellites_total or 0
            })
            table.insert(data, {
                field_meaning = excloud.FIELD_MEANINGS.SATELLITES_VISIBLE,
                data_type = excloud.DATA_TYPES.INTEGER,
                value = location.satellites_visible or 0
            })
        end
    else
        log.info("REPORT", "无有效位置数据")
    end

    -- 发送
    local ok, err = excloud_module.send(data, false)

    if ok then
        packet_count = packet_count + 1
        global_config.inc_report_count()
        log.info("REPORT", "状态上报发送成功, 数据包计数:", packet_count)
    else
        log.error("REPORT", "状态上报发送失败:", err)
    end

    return ok, err
end

-- 上报定位信息
function report.send_location()
    log.info("REPORT", "发送位置上报")

    local location = mygps.get_location()

    if location.lat == 0 and location.lng == 0 then
        log.warn("REPORT", "无有效位置可上报")
        return false, "无位置"
    end

    local ok, err = excloud_module.send_location(
        location.lat,
        location.lng,
        location.accuracy,
        location.source
    )

    if ok then
        log.info("REPORT", "位置上报发送成功:", location.lat, location.lng)
    else
        log.error("REPORT", "位置上报发送失败:", err)
    end

    return ok, err
end

-- 上报电池状态
function report.send_battery()
    log.info("REPORT", "发送电池上报")

    local battery = mypower.get_battery_level()
    local is_charging = mypower.is_charging()

    local ok, err = excloud_module.send_battery(battery, is_charging)

    if ok then
        log.info("REPORT", "电池上报发送成功:", battery .. "%", "充电中:", is_charging)
    else
        log.error("REPORT", "电池上报发送失败:", err)
    end

    return ok, err
end

-- 上报系统状态
function report.send_system_status()
    log.info("REPORT", "发送系统状态上报")

    local system_info = get_system_info()

    local ok, err = excloud_module.send_system_status(system_info)

    if ok then
        log.info("REPORT", "系统状态上报发送成功")
    else
        log.error("REPORT", "系统状态上报发送失败:", err)
    end

    return ok, err
end

-- 定时上报任务
-- 上报前流程：
--   ① 刷新 LBS 定位（同步阻塞，最长 LBS_TIMEOUT_MS）
--   ② 判断是否需要触发 GNSS（每 GNSS_REQUEST_INTERVAL 一次，同步阻塞最长 60s）
--   ③ 调用 send_status 发送 TLV（含定位结果 + GNSS_RESULT）
-- @param reason string 本次上报原因（REPORT_REASON 枚举值），默认 TIMER
local function report_task(reason)
    current_report_reason = reason or REPORT_REASON.TIMER
    log.info("REPORT", "==> 上报任务运行中, reason=" .. current_report_reason)

    if not excloud_module.is_connected() then
        log.warn("REPORT", "未连接云平台, 跳过上报")
        return
    end

    -- ① 上报前刷新 LBS（同步）
    log.info("REPORT", "[1/3] 上报前刷新 LBS ...")
    local lbs_ok = mygps.do_lbs_once_sync()
    log.info("REPORT", "[1/3] LBS 完成, ok=" .. tostring(lbs_ok))

    -- ② 判断是否需要触发 GNSS（每 30min 一次）
    local now_sec = os.time()
    local need_gnss = (last_gnss_trigger_sec == 0)
                      or ((now_sec - last_gnss_trigger_sec) * 1000 >= GNSS_REQUEST_INTERVAL)
    if need_gnss then
        log.info("REPORT", "[2/3] 触发 GNSS 定位 (距上次=" .. (now_sec - last_gnss_trigger_sec) .. "s)")
        last_gnss_trigger_sec = now_sec
        local gnss_ok = mygps.do_gnss_once_sync()
        log.info("REPORT", "[2/3] GNSS 完成, ok=" .. tostring(gnss_ok))
    else
        local remain_s = math.floor((GNSS_REQUEST_INTERVAL - (now_sec - last_gnss_trigger_sec) * 1000) / 1000)
        log.info("REPORT", "[2/3] 跳过 GNSS（距下次还需 " .. remain_s .. "s）")
    end

    -- ③ 发送 TLV
    log.info("REPORT", "[3/3] 发送 TLV ...")
    report.send_status()
end

-- 根据运动状态动态计算下一次上报等待时间（毫秒）
-- 对齐花生宠物业务逻辑 2.10.3：智能模式动态上报间隔
local function get_next_interval()
    if not SMART_INTERVAL_ENABLED then
        return report_interval
    end

    if gsensor and gsensor.is_moving and gsensor.is_moving() then
        log.info("REPORT", "运动状态: 运动中, 下次间隔=" .. (REPORT_INTERVAL_MOVING / 1000) .. "s")
        return REPORT_INTERVAL_MOVING
    else
        log.info("REPORT", "运动状态: 静止, 下次间隔=" .. (REPORT_INTERVAL_STATIC / 1000) .. "s")
        return REPORT_INTERVAL_STATIC
    end
end

-- 判断当前是否仍处于震动冷却期
-- @return boolean true=冷却中（拒绝震动触发上报），false=已过冷却期
local function in_motion_cooldown()
    if last_motion_report_sec <= 0 then
        return false
    end
    local now_sec = os.time()
    local elapsed_ms = (now_sec - last_motion_report_sec) * 1000
    if elapsed_ms < 0 then
        -- 系统时间被回调（如 NTP 校时），保守认为已经过冷却期
        return false
    end
    return elapsed_ms < MOTION_REPORT_COOLDOWN
end

-- 获取冷却期剩余时间（毫秒，仅用于日志展示）
local function get_cooldown_remain_ms()
    local now_sec = os.time()
    local elapsed_ms = (now_sec - last_motion_report_sec) * 1000
    if elapsed_ms < 0 then return 0 end
    local remain = MOTION_REPORT_COOLDOWN - elapsed_ms
    return remain > 0 and remain or 0
end

-- 启动定时上报
function report.start()
    log.info("REPORT", "启动上报模块...")

    -- 内存计数：每次开机从0开始
    reboot_count = reboot_count + 1
    log.info("REPORT", "本次开机重启计数:", reboot_count)

    -- 记录首次开机时间（用于在线时间字段）
    -- 注意：这里的"首次"是指本次进程启动，关机/重启后会重置
    if boot_time_sec == 0 then
        boot_time_sec = os.time()
        log.info("REPORT", "首次开机时间戳:", boot_time_sec, "(用于在线时间计算)")
    end

    -- 心跳由 excloud 库自带的 excloud.start_heartbeat() 接管（在 excloud_module.init 中启动）
    -- 不再在业务层自管心跳，避免业务层"孤立时间戳"包污染上报序列

    log.info("REPORT", "智能上报开关:", SMART_INTERVAL_ENABLED,
                       "运动间隔:", REPORT_INTERVAL_MOVING, "ms",
                       "静止间隔:", REPORT_INTERVAL_STATIC, "ms",
                       "震动冷却期:", MOTION_REPORT_COOLDOWN, "ms")

    if report_timer then
        sys.timerStop(report_timer)
        report_timer = nil
    end

    -- 主上报任务：动态间隔 + 震动事件唤醒提前上报（带 10min 冷却期）
    sys.taskInit(function()
        log.info("REPORT", "等待云平台连接...")
        sys.waitUntil("EXCLOUD_CONNECTED")
        log.info("REPORT", "云平台已连接，开始上报")

        -- 首次开机上报，标记为 PWRKEY（用 pcall 包裹，避免抛错导致 task 静默退出）
        local pok, perr = pcall(report_task, REPORT_REASON.PWRKEY)
        if not pok then
            log.error("REPORT", "首次 PWRKEY 上报抛错:", tostring(perr))
        end

        while true do
            local interval = get_next_interval()
            -- 等待间隔到期，或被 GSENSOR_MOTION 事件提前唤醒
            local awakened = sys.waitUntil("GSENSOR_MOTION", interval)
            log.info("REPORT", "等待事件唤醒, 唤醒原因:",
                               awakened and "GSENSOR_MOTION" or "定时到期",
                               "等待时间:", interval)

            -- 用 pcall 包裹上报，避免单次上报抛错导致整个循环终止
            local task_ok, task_err
            if awakened then
                -- 震动事件触发：先判断冷却期
                if in_motion_cooldown() then
                    local remain_s = math.floor(get_cooldown_remain_ms() / 1000)
                    log.info("REPORT", "震动事件触发但仍在冷却期内, 剩余=" .. remain_s
                                       .. "s, 忽略本次震动上报")
                else
                    log.info("REPORT", "震动事件唤醒，提前触发一次上报（启动 10min 冷却期）")
                    last_motion_report_sec = os.time()
                    task_ok, task_err = pcall(report_task, REPORT_REASON.MOTION)
                end
            else
                -- 定时到期触发
                task_ok, task_err = pcall(report_task, REPORT_REASON.TIMER)
            end

            if task_ok == false then
                log.error("REPORT", "本次上报抛错:", tostring(task_err))
            end
        end
    end)

    -- ========== 独立 task：监听 WAKEUP0 中断触发的 GPS_TRIGGER 事件 ==========
    -- 设计要点：
    --   1) 与主上报循环完全独立，不影响 5min 定时与震动冷却
    --   2) 不受 30min GNSS 节流限制——WAKEUP0 中断必触发一次 GNSS
    --   3) 定位成功/失败都强制 send_status 一次（失败时经纬度=0,0 也上报）
    --   4) 用 pcall 包裹防止抛错导致 task 静默退出
    sys.taskInit(function()
        while true do
            sys.waitUntil("GPS_TRIGGER_REQ")
            log.info("REPORT", "收到 GPS_TRIGGER_REQ 中断事件，强制 GNSS 定位 + 立即上报")

            if not excloud_module.is_connected() then
                log.warn("REPORT", "[GPS_TRIGGER] 未连接云平台，跳过本次")
            else
                -- 强制刷新最近一次 GNSS 时间戳（确保下次 30min 节流逻辑正确）
                last_gnss_trigger_sec = os.time()

                -- ① 强制 GNSS 同步定位（最长阻塞 60s）
                local gok = mygps.do_gnss_once_sync()
                log.info("REPORT", "[GPS_TRIGGER] GNSS 完成, ok=" .. tostring(gok)
                                   .. "（无论成功失败都继续上报）")

                -- ② 发送 TLV：失败时 GNSS_INFO 字段为 "0.000000,0.000000"
                current_report_reason = REPORT_REASON.GPS_TRIGGER
                local pok, perr = pcall(report.send_status)
                if not pok then
                    log.error("REPORT", "[GPS_TRIGGER] send_status 抛错: " .. tostring(perr))
                end
            end
        end
    end)
end

-- 停止定时上报
function report.stop()
    log.info("REPORT", "停止上报模块...")

    if report_timer then
        sys.timerStop(report_timer)
        report_timer = nil
    end

    log.info("REPORT", "上报模块已停止")
end

-- 设置上报间隔（仅运行期生效，不持久化）
function report.set_interval(interval)
    log.info("REPORT", "设置上报间隔为:", interval)

    report_interval = interval

    if report_timer then
        report.stop()
        report.start()
    end
end

-- 获取上报间隔
function report.get_interval()
    return report_interval
end

-- 获取包计数器
function report.get_packet_count()
    return packet_count
end

-- 获取重启次数
function report.get_reboot_count()
    return reboot_count
end

-- 获取震动冷却期剩余秒数（0=无冷却或已过期）
function report.get_motion_cooldown_remain()
    return math.floor(get_cooldown_remain_ms() / 1000)
end

-- 重置震动冷却期（立即解除）
function report.reset_motion_cooldown()
    last_motion_report_sec = 0
    log.info("REPORT", "震动冷却期已手动重置")
end

-- 手动触发一次上报（如远程命令 GET_STATUS）
-- 不影响震动冷却期状态
function report.trigger_manual_report()
    sys.taskInit(function()
        report_task(REPORT_REASON.MANUAL)
    end)
end

-- 对外暴露上报原因枚举（供其他模块调用）
report.REPORT_REASON = REPORT_REASON

return report
