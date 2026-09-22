--[[
@module  protocol_app
@summary AirCloud 业务协议处理模块
@version 1.0
@date    2026.09.18
@author  嵌入式软件设计开发代理
@usage
根据《网络通信协议文档》实现 AirCloud 业务协议处理（excloud 已封装报文层）：
- 周期上报：电压(799)、工作状态(265)，1 分钟
- 状态即时上报：电压(799)、工作状态(265)，变化时立即上报
- 事件上报：设定电压(800)，状态变化时
- 设备信息上报：IMEI(798)、ICCID(783)，鉴权成功后开机上报一次
- 控制命令：解析 Type=19（value 为顶层裸数组 JSON：field_meaning=265 工作状态 / 800 设定电压）
- 控制回执：构造 Type=20（嵌套子 TLV 265 工作状态 / 800 设定电压，回显执行后实际值）
- 数据上报：单向上报，无需应答、不重传

订阅消息：
- "AIRCLOUD_MSG"           -- 解析云端下行消息 {tlvs, header}
- "CTRL_CMD_RESULT"        -- 控制命令执行结果 → 构造 Type=20 回执 {work_status, set_voltage}
- "REPORT_PERIODIC"        -- 周期上报触发 {voltage, work_status}
- "REPORT_STATUS"          -- 电压/工作状态变化即时上报触发 {voltage, work_status}
- "REPORT_EVENT"           -- 事件上报触发 {field, value}
- "REPORT_DEVICE_INFO"     -- 设备信息上报触发
- "NET_4G_SIGNAL_STATUS"   -- 4G 信号状态（csq_level, csq）（netdrv_4g 发布，缓存原始 CSQ 供上报 782）
- "NET_STATUS"             -- 网络总状态（netdrv_wifi 发布，缓存 WiFi RSSI 供上报 782）

发布消息：
- "CTRL_CMD_RECV"          -- 收到控制命令 {ctrl_fields}
]]

-- 注意：json 为 LuatOS 核心库（osapi/core/json，全局内置），禁止显式 require
local excloud = require "excloud"
local aircloud_app = require "aircloud_app"

local protocol_app = {}

-- 上报字段常量（协议附录 A.2）
local FIELD = {
    WORK_STATUS = 265,       -- 工作状态（上/下行：上报 + Type=19 控制命令下发目标）
    GNSS_LONGITUDE = 512,    -- 经度（上行，ASCII 字符串，基站定位 LBS）
    GNSS_LATITUDE  = 513,    -- 纬度（上行，ASCII 字符串，基站定位 LBS）
    ICCID       = 783,       -- SIM 卡 ICCID（上行）
    IMEI        = 798,       -- 设备号/IMEI（上行）
    VOLTAGE     = 799,       -- 电压（上行）
    VERSION     = 1027,      -- 版本号（固件文件名+项目名+版本号，上行，ASCII 字符串）
    SET_VOLTAGE = 800,       -- 高压板设定电压（上/下行：上报 + Type=19 控制命令下发目标，自主补充）
    NETWORK_TYPE    = 781,   -- 联网方式（上行：1=4G，2=WiFi，3=以太网）
    SIGNAL_STRENGTH = 782,   -- 信号强度（上行：当前联网方式的信号强度，统一 0~31 刻度；4G=CSQ 原始值，WiFi=RSSI 折算）
}

-- 联网方式（字段 781）取值
local NET_TYPE_4G   = 1
local NET_TYPE_WIFI = 2
local NET_TYPE_ETH  = 3   -- 以太网（本项目真机不使用；PC 模拟器默认网卡为 socket.ETH0）

-- 数据上报为单向上报（协议 7.6：服务端不回应答，设备不重传）

--[[
安全调用可能缺失的库函数（PC 模拟器只实现部分接口，缺失/异常时返回 nil 而不中断任务）

说明：模拟器的 netdrv_pc 只提供 mobile.imei 桩函数、未提供 mobile.iccid；
      rtos.firmware / rtos.version 等在模拟器上也可能不存在，直接调用会抛异常。

@local
@function safe_call
@param fn function|nil 目标函数（可为 nil）
@return any 首个返回值；函数不存在或调用异常时返回 nil
]]
local function safe_call(fn, ...)
    if type(fn) ~= "function" then
        return nil
    end
    local ok, v = pcall(fn, ...)
    if not ok then
        return nil
    end
    return v
end

-- 整数子 TLV 数据类型（协议 2.3.3：0000 = 整数）
local TLV_TYPE_INTEGER = 0x0

--[[
解析子 TLV 二进制（协议 2.3：Type(2B) + Length(2B) + Value，大端序）

@local
@function parse_sub_tlvs
@param data_str string 子 TLV 二进制字符串
@return table 子 TLV 列表 {field=..., type=..., value=...}
]]
local function parse_sub_tlvs(data_str)
    local result = {}
    local pos = 1
    local len = #data_str
    while pos + 3 <= len do
        local type_raw = (string.byte(data_str, pos) << 8) | string.byte(data_str, pos + 1)
        local length = (string.byte(data_str, pos + 2) << 8) | string.byte(data_str, pos + 3)
        -- 越界保护
        if pos + 3 + length > len then
            break
        end
        local field = type_raw & 0x0FFF            -- bit0-11 字段含义
        local data_type = (type_raw >> 12) & 0x0F  -- bit12-15 数据类型
        local value_str = string.sub(data_str, pos + 4, pos + 3 + length)
        -- 根据数据类型解析值
        local value
        if data_type == TLV_TYPE_INTEGER then
            -- 整数（有符号，大端序）
            value = 0
            for i = 1, length do
                value = (value << 8) | string.byte(value_str, i)
            end
            -- 负数处理
            if length > 0 and (string.byte(value_str, 1) & 0x80) ~= 0 then
                value = value - (1 << (length * 8))
            end
        else
            -- 其他类型原样保留字符串
            value = value_str
        end
        table.insert(result, {field = field, type = data_type, value = value})
        pos = pos + 4 + length
    end
    return result
end

--[[
构造子 TLV 二进制（协议 2.3：Type(2B) + Length(2B) + Value，大端序）

@local
@function build_sub_tlv
@param field number 字段含义
@param data_type number 数据类型
@param value number/string 字段值
@return string 子 TLV 二进制字符串
]]
local function build_sub_tlv(field, data_type, value)
    -- Type = (data_type << 12) | field
    local type_raw = (data_type << 12) | field
    local value_str
    if data_type == TLV_TYPE_INTEGER then
        -- 整数（2 字节，大端序）
        value_str = string.char((value >> 8) & 0xFF, value & 0xFF)
    else
        value_str = tostring(value)
    end
    return string.char(
        (type_raw >> 8) & 0xFF, type_raw & 0xFF,
        (#value_str >> 8) & 0xFF, #value_str & 0xFF
    ) .. value_str
end

--[[
构造业务上报 TLV（整数类型）

@local
@function make_tlv
@param field number 字段含义
@param value number 字段值
@return table TLV 表
]]
local function make_tlv(field, value)
    return {
        field_meaning = field,
        data_type = excloud.DATA_TYPES.INTEGER,
        value = value,
    }
end

--[[
构造业务上报 TLV（ASCII 字符串类型，用于 IMEI/ICCID 等数字字符串）

@local
@function make_str_tlv
@param field number 字段含义
@param value string 字段值
@return table TLV 表
]]
local function make_str_tlv(field, value)
    return {
        field_meaning = field,
        data_type = excloud.DATA_TYPES.ASCII,
        value = tostring(value),
    }
end

--[[
发送 TLV 列表到云端（单向上报，无需应答，不重传）

@local
@function send_tlvs
@param tlv_list table TLV 列表
@return boolean 是否发送成功
]]
local function send_tlvs(tlv_list)
    local ok, err_msg = aircloud_app.send(tlv_list, false)
    if not ok then
        log.warn("protocol_app", "发送失败:", err_msg)
        aircloud_app.mtn_log("send", "发送失败: " .. tostring(err_msg))
        return false
    end
    return true
end

-- 最近一次基站定位结果（由 lbs_app 通过 LOCATION_UPDATED 广播，经纬度为 number）
local location = { valid = false, lat = nil, lng = nil }

--[[
基站定位结果更新（lbs_app 发布 LOCATION_UPDATED）

@local
@function on_location_updated
@param lat number 纬度
@param lng number 经度
@return nil
]]
local function on_location_updated(lat, lng)
    if lat and lng then
        location.lat = lat
        location.lng = lng
        location.valid = true
        log.info("protocol_app", "定位更新: 纬度=" .. tostring(lat) .. ", 经度=" .. tostring(lng))
    end
end

--[[
向 TLV 列表追加经纬度字段（ASCII 字符串，仅在定位有效时追加）
协议字段：512 GNSS_LONGITUDE（经度）、513 GNSS_LATITUDE（纬度）

@local
@function append_location_tlvs
@param tlv_list table TLV 列表
@return nil
]]
local function append_location_tlvs(tlv_list)
    if not location.valid then
        return
    end
    table.insert(tlv_list, make_str_tlv(FIELD.GNSS_LONGITUDE, string.format("%.6f", location.lng)))
    table.insert(tlv_list, make_str_tlv(FIELD.GNSS_LATITUDE, string.format("%.6f", location.lat)))
end

-- 当前网络信号缓存（由 netdrv_4g / netdrv_wifi 广播更新，供上报字段 781/782 使用）
-- csq：4G 原始 CSQ（0~31，99=无信号/不可测）
-- wifi_rssi：WiFi 信号强度（dBm，nil=暂无有效值）
local net_signal = { csq = nil, wifi_rssi = nil }

--[[
4G 信号状态更新（netdrv_4g 发布 NET_4G_SIGNAL_STATUS）

@local
@function on_4g_signal_status
@param csq_level number 4G 信号等级（-1=无卡/无信号，1-5=信号等级，供 UI 使用，本模块不使用）
@param csq number 4G 原始 CSQ（0~31，99=无信号/不可测）
@return nil
]]
local function on_4g_signal_status(csq_level, csq)
    if csq then
        net_signal.csq = csq
    end
end

--[[
网络总状态更新（netdrv_wifi 发布 NET_STATUS，本模块仅缓存 WiFi 信号强度）

@local
@function on_net_status
@param wifi_connected boolean WiFi 连接状态
@param wifi_ssid string 当前连接的 SSID
@param wifi_rssi number WiFi 信号强度（dBm）
@param g4_connected boolean 4G 连接状态
@param adapter number 当前默认网卡
@return nil
]]
local function on_net_status(wifi_connected, wifi_ssid, wifi_rssi, g4_connected, adapter)
    net_signal.wifi_rssi = wifi_rssi
end

-- WiFi 信号强度（RSSI，dBm）折算为 0~31（与 4G CSQ 统一刻度）的区间边界
local RSSI_MAX_DBM = -50    -- 折算上限：rssi >= -50 视为满值 31
local RSSI_MIN_DBM = -100   -- 折算下限：rssi <= -100 视为 0

--[[
WiFi 信号强度（RSSI，dBm）折算为 0~31（与 4G CSQ 统一刻度）

折算规则（线性截断 + 四舍五入）：
- rssi >= -50  → 31
- rssi <= -100 → 0
- 中间          → round((rssi + 100) * 31 / 50)
无有效 RSSI（nil）时按最弱 0 处理。

@local
@function rssi_to_signal
@param rssi number|nil WiFi 信号强度（dBm）
@return number 折算后的信号强度（0~31）
]]
local function rssi_to_signal(rssi)
    if not rssi then
        return 0
    end
    if rssi >= RSSI_MAX_DBM then
        return 31
    end
    if rssi <= RSSI_MIN_DBM then
        return 0
    end
    return math.floor((rssi - RSSI_MIN_DBM) * 31 / (RSSI_MAX_DBM - RSSI_MIN_DBM) + 0.5)
end

--[[
向 TLV 列表追加联网方式（781）与信号强度（782）

联网方式取上报时刻的默认网卡（socket.dft()），保证与"实际承载云连接的网卡"一致：
- socket.LWIP_STA（WiFi）：781=2，782=WiFi RSSI 折算值（0~31）
- socket.LWIP_GP（4G）：781=1，782=CSQ 原始值（0~31，99=无信号/不可测）
- 无默认网卡：不追加（上报依赖云连接已建立，正常不会出现）

@local
@function append_network_tlvs
@param tlv_list table TLV 列表
@return nil
]]
local function append_network_tlvs(tlv_list)
    local adapter = socket.dft()
    if adapter == socket.LWIP_STA then
        -- WiFi 联网：联网方式=2，信号强度=WiFi RSSI 折算值
        table.insert(tlv_list, make_tlv(FIELD.NETWORK_TYPE, NET_TYPE_WIFI))
        table.insert(tlv_list, make_tlv(FIELD.SIGNAL_STRENGTH, rssi_to_signal(net_signal.wifi_rssi)))
    elseif adapter == socket.LWIP_GP then
        -- 4G 联网：联网方式=1，信号强度=CSQ 原始值
        table.insert(tlv_list, make_tlv(FIELD.NETWORK_TYPE, NET_TYPE_4G))
        table.insert(tlv_list, make_tlv(FIELD.SIGNAL_STRENGTH, net_signal.csq or 99))
    elseif adapter == socket.ETH0 then
        -- 以太网（PC 模拟器默认网卡，真机不加载以太网驱动故不会走到此分支）：
        -- 联网方式=3；模拟器无射频信号，信号强度按 0 上报，保证 781/782 成对出现
        table.insert(tlv_list, make_tlv(FIELD.NETWORK_TYPE, NET_TYPE_ETH))
        table.insert(tlv_list, make_tlv(FIELD.SIGNAL_STRENGTH, 0))
    end
end

--[[
状态上报：电压(799) + 工作状态(265) + 设定电压(800) + 联网方式(781) + 信号强度(782)
（协议 7.5：周期/鉴权成功/变化时上报；经纬度、网络信息在可用时一并追加）

@local
@function report_periodic
@param voltage number 实际输出电压（V）
@param work_status number 工作状态（1=开机中，0=关机中，255=未同步）
@param set_voltage number 设定电压（V）
@return nil
]]
local function report_periodic(voltage, work_status, set_voltage)
    local tlv_list = {
        make_tlv(FIELD.VOLTAGE, voltage),
        make_tlv(FIELD.WORK_STATUS, work_status),
        make_tlv(FIELD.SET_VOLTAGE, set_voltage),
    }
    -- 追加经纬度（已成功定位时一并上报）
    append_location_tlvs(tlv_list)
    -- 追加联网方式（781）与信号强度（782）
    append_network_tlvs(tlv_list)
    send_tlvs(tlv_list)
end

--[[
事件上报：设定电压(800) 等（协议 7.5：状态变化时上报）

@local
@function report_event
@param field number 字段含义
@param value number 字段值
@return nil
]]
local function report_event(field, value)
    local tlv_list = {
        make_tlv(field, value),
    }
    if send_tlvs(tlv_list) then
        aircloud_app.mtn_log("report", "事件上报: 字段=" .. field .. ", 值=" .. value)
    end
end

--[[
设备信息上报：IMEI(798) + ICCID(783) + 版本号(1027)（协议 7.5：开机上报一次）

@local
@function report_device_info
@return nil
]]
local function report_device_info()
    -- 获取模组 IMEI 与 SIM 卡 ICCID（mobile 核心库）
    -- ⚠️ PC 模拟器兼容：模拟器的 netdrv_pc 只提供 mobile.imei 桩函数、未提供 mobile.iccid，
    --    故统一用 safe_call 保护（缺失/异常返回 nil），避免设备信息上报时崩溃
    local imei = safe_call(_G.mobile and _G.mobile.imei)
    local iccid = safe_call(_G.mobile and _G.mobile.iccid)
    log.info("protocol_app", "设备信息: IMEI=" .. tostring(imei) .. ", ICCID=" .. tostring(iccid))

    -- 版本号（协议 7.4：Type=1027，ASCII 字符串）
    -- 格式：内核固件文件名 + 空格 + 脚本项目名 + 空格 + 脚本版本号
    -- 示例：Luatos-SoC_V2050_Air8000_114 ART_ELECTRIC_DEVICE 001.999.000
    local fw_name = safe_call(rtos.firmware) or ""
    -- rtos.version(true) 返回 (内核名, 版本号) 两个值，需单独处理多返回值（模拟器上可能未实现）
    local fw_ver = ""
    if type(rtos.version) == "function" then
        local ok_ver, _, v = pcall(rtos.version, true)
        if ok_ver and v then
            fw_ver = tostring(v)
        end
    end
    local fw_full = fw_name .. "_" .. fw_ver
    local script_version = tostring(_G.PROJECT or "unknown") .. " " .. tostring(_G.VERSION or "0.0.0")
    local combined_version = fw_full .. " " .. script_version
    log.info("protocol_app", "版本号: " .. combined_version)

    local tlv_list = {}
    if imei and #imei > 0 then
        table.insert(tlv_list, make_str_tlv(FIELD.IMEI, imei))
    end
    if iccid and #iccid > 0 then
        table.insert(tlv_list, make_str_tlv(FIELD.ICCID, iccid))
    end
    -- 版本号上报（与设备号、ICCID 一起）
    table.insert(tlv_list, make_str_tlv(FIELD.VERSION, combined_version))

    if #tlv_list > 0 then
        if send_tlvs(tlv_list) then
            aircloud_app.mtn_log("device", "设备信息上报: IMEI=" .. tostring(imei) .. ", ICCID=" .. tostring(iccid) .. ", VERSION=" .. combined_version)
        end
    end
end

--[[
发送控制回执（协议 8.4.2：Type=20，V 嵌套 265 工作状态 + 800 设定电压，回显执行后实际值）

@local
@function send_control_response
@param work_status number 当前工作状态（1=开机中，0=关机中）
@param set_voltage number 当前设定电压（V）
@return nil
]]
local function send_control_response(work_status, set_voltage)
    -- 构造子 TLV 二进制（回显 265 工作状态 + 800 设定电压）
    local sub_tlv_str = build_sub_tlv(FIELD.WORK_STATUS, TLV_TYPE_INTEGER, work_status)
        .. build_sub_tlv(FIELD.SET_VOLTAGE, TLV_TYPE_INTEGER, set_voltage)
    -- 构造 Type=20 TLV（协议 8.3：控制回执数据类型为 ASCII 字符串）
    local tlv_list = {
        {
            field_meaning = excloud.FIELD_MEANINGS.CONTROL_RESPONSE,
            data_type = excloud.DATA_TYPES.ASCII,
            value = sub_tlv_str,
        }
    }
    local ok, err_msg = aircloud_app.send(tlv_list, false)
    if not ok then
        log.warn("protocol_app", "发送控制回执失败:", err_msg)
        aircloud_app.mtn_log("ctrl", "控制回执发送失败: " .. tostring(err_msg))
        return
    end
    log.info("protocol_app", "控制回执已发送: work_status=" .. work_status .. ", set_voltage=" .. set_voltage)
    aircloud_app.mtn_log("ctrl", "控制回执: 工作状态=" .. work_status .. ", 设定电压=" .. set_voltage)
end

--[[
处理云端下行消息（协议 8.4.1：Type=19 控制命令）

@local
@function handle_aircloud_msg
@param tlvs table TLV 列表
@param header table 消息头
@return nil
]]
local function handle_aircloud_msg(tlvs, header)
    if not tlvs then
        return
    end
    for _, tlv in ipairs(tlvs) do
        log.info("protocol_app", "TLV字段", "含义:", tlv.field, "类型:", tlv.type, "值:", tostring(tlv.value))

        -- 控制命令（协议 8.3：Type=19，value 内嵌 265 工作状态 / 800 设定电压）
        if tlv.field == excloud.FIELD_MEANINGS.CONTROL_COMMAND then
            --[[ 平台下发的 value 是「顶层裸数组的 JSON 字符串」，键名即 excloud 约定：
                   [{"field_meaning":265,"data_type":0,"value":1}]
                 · field_meaning=265 工作状态（1=开机 / 0=关机）、800 设定电压（0~6000）
                 · data_type=0 整数；value 为字段值
                 解析顺序（逐级兜底，记录命中路径用于诊断）：
                   ① JSON 字符串（平台实际下发格式）
                   ② 已解析表（excloud 直接给出 table 时）
                   ③ 二进制子 TLV（协议 2.3：Type(2B)+Length(2B)+Value，历史/自定义格式）
                   ④ 正则兜底（json 库不可用/报文含非法字符等极端情况）
                 ⚠️ 四级全部失败时必须告警：原实现静默丢弃，导致"云端下发命令但设备无反应"极难定位。 ]]
            local ctrl_fields = {}
            local raw = tlv.value
            local items = nil
            local path = "unknown"
            if type(raw) == "string" then
                local ok_json, arr = pcall(json.decode, raw)
                if ok_json and type(arr) == "table" then
                    items = arr
                    path = "JSON"
                end
            elseif type(raw) == "table" then
                items = raw
                path = "table"
            end

            if items then
                for _, sub in ipairs(items) do
                    -- 键名兼容 field_meaning（excloud 约定）与 field（内部精简写法）
                    local fm = tonumber(sub.field_meaning or sub.field)
                    if fm == FIELD.WORK_STATUS or fm == FIELD.SET_VOLTAGE then
                        -- JSON 里的数值可能是数字或字符串，统一转数字后再交给业务层比较
                        local v = tonumber(sub.value)
                        ctrl_fields[fm] = (v ~= nil) and v or sub.value
                    end
                end
            end

            if not next(ctrl_fields) and type(raw) == "string" then
                -- ③ 二进制子 TLV 解析（Type(2B) + Length(2B) + Value，大端序）
                local parsed = parse_sub_tlvs(raw)
                for _, sub in ipairs(parsed) do
                    if sub.field == FIELD.WORK_STATUS or sub.field == FIELD.SET_VOLTAGE then
                        ctrl_fields[sub.field] = sub.value
                    end
                end
                if next(ctrl_fields) then
                    path = "binary"
                end
            end

            if not next(ctrl_fields) and type(raw) == "string" then
                -- ④ 正则兜底：直接抽取同一对象内的 "field_meaning":.. 与 "value":..
                for fm_str, v_str in string.gmatch(raw, '"field_meaning"%s*:%s*(%d+)[^}]*"value"%s*:%s*(-?%d+)') do
                    local fm = tonumber(fm_str)
                    local v = tonumber(v_str)
                    if fm and v and (fm == FIELD.WORK_STATUS or fm == FIELD.SET_VOLTAGE) then
                        ctrl_fields[fm] = v
                    end
                end
                if next(ctrl_fields) then
                    path = "regex"
                end
            end

            if next(ctrl_fields) then
                -- 打印控制字段（含解析路径，便于与云端报文比对）
                local desc = {}
                for f, v in pairs(ctrl_fields) do
                    table.insert(desc, "字段" .. f .. "=" .. tostring(v))
                end
                log.info("protocol_app", "收到控制命令(" .. path .. "): " .. table.concat(desc, ", "))
                -- 发布给业务模块执行（协议 8.5）
                sys.publish("CTRL_CMD_RECV", ctrl_fields)
            else
                -- 未解析出任何有效控制字段：必须告警（含 value 类型与原始内容），否则无法定位
                local detail = "value类型=" .. type(raw) .. ", 原始内容=" .. tostring(raw)
                log.warn("protocol_app", "控制命令(Type=19)未解析出有效字段, " .. detail)
                aircloud_app.mtn_log("ctrl", "控制命令(Type=19)未解析出有效字段, " .. detail)
            end
        end
    end
end

-- 对外接口：周期上报（业务模块调用）
function protocol_app.report_periodic(voltage, work_status, set_voltage)
    report_periodic(voltage, work_status, set_voltage)
end

-- 对外接口：事件上报（业务模块调用）
function protocol_app.report_event(field, value)
    report_event(field, value)
end

-- 对外接口：设备信息上报（业务模块调用）
function protocol_app.report_device_info()
    report_device_info()
end

-- 对外接口：发送控制回执（业务模块调用）
function protocol_app.send_control_response(work_status, set_voltage)
    send_control_response(work_status, set_voltage)
end

-- 订阅消息
sys.subscribe("AIRCLOUD_MSG", handle_aircloud_msg)
sys.subscribe("REPORT_PERIODIC", report_periodic)
sys.subscribe("REPORT_STATUS", report_periodic)
sys.subscribe("REPORT_EVENT", report_event)
sys.subscribe("REPORT_DEVICE_INFO", report_device_info)
sys.subscribe("CTRL_CMD_RESULT", send_control_response)
sys.subscribe("LOCATION_UPDATED", on_location_updated)
sys.subscribe("NET_4G_SIGNAL_STATUS", on_4g_signal_status)
sys.subscribe("NET_STATUS", on_net_status)

-- 版本指纹日志：用于确认设备烧录的脚本是否包含 Type=19 控制命令「四级兜底解析」（变更 8）
-- 排查"云端下发命令但设备无反应"时，先看这一行；若开机日志中缺失该行，说明跑的不是最新脚本
log.info("protocol_app", "控制命令解析器: JSON/table/binary/regex 四级兜底已启用")

return protocol_app
