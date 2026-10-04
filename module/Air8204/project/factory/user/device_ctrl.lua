--[[
@module  device_ctrl
@summary 平台下行命令处理模块（远程控制 + 基础信息查询）
@version 1.0
@date    2026.09.28
@usage
本模块处理 excloud 云平台下发的 CONTROL_COMMAND（field=19）控制命令：
解析命令字 → 执行对应动作 → 返回真实执行结果文本（由 excloud_app.lua 通过
CONTROL_RESPONSE（field=20）回执平台）。

命令字约定（统一小写 + 下划线，与 config.lua 既有取值风格一致）：

  一、控制类（写 config.record_ctrl，由 gpio_util.recording_mode_chack() 生效）
    recording        远程开启录音
    not_recording    远程关闭录音
    record_local     恢复本地 GPIO22 开关控制录音（record_ctrl = -1）

  二、查询类（触发一次数据上报，回执告知平台已上报）
    get_info           读取全部基础信息（聚合上报，字段见 handlers["get_info"]）
    get_version        读取固件版本（field 1027）
    get_battery        读取电池电量（field 771）
    get_signal         读取 4G 信号质量（field 782）
    get_record_count   读取录音文件数量（field 797）

  三、未知命令：回执 "未知命令: xxx"，不执行任何动作（不再无脑回"命令执行成功"）。

上报字段全部使用 excloud 协议已定义的标准字段（FIELD_MEANINGS），无需扩展协议。

依赖（均为本工程全局变量，加载顺序由 card_main.lua 保证）：
  config / gpio_util / RecordingManager / gps / lbs_util / excloud
]]

local device_ctrl = {}

--[[
构建单个 TLV 字段

@param meaning number  field_meaning，取自 excloud.FIELD_MEANINGS
@param dtype   number  data_type，取自 excloud.DATA_TYPES
@param value   any     字段值
@return table TLV 字段表
]]
local function field(meaning, dtype, value)
    return {
        field_meaning = meaning,
        data_type = dtype,
        value = value
    }
end

--[[ 读取固件版本字符串（PROJECT + VERSION，均为 main.lua 定义的全局变量） ]]
local function read_version()
    return tostring(PROJECT or "") .. " " .. tostring(VERSION or "")
end

--[[ 读取开机原因（与 app.lua 状态上报中的 appVersion 字段同源） ]]
local function read_boot_reason()
    local r1, r2, r3 = pm.lastReson()
    return "reason" .. r1 .. r2 .. r3
end

--[[ 读取电池电量（百分比） ]]
local function read_battery()
    return gpio_util.get_battery_voltage()
end

--[[ 读取 4G 信号质量（CSQ，0~31） ]]
local function read_signal()
    return mobile.csq() or 0
end

--[[ 读取录音文件数量 ]]
local function read_record_count()
    local records = RecordingManager.getAllRecords()
    return records and #records or 0
end

--[[
读取磁盘信息

@return string 总容量（如 "3785 MB"），失败时返回 ""
@return string 剩余容量（如 "3785 MB"），失败时返回 ""
]]
local function read_disk()
    local data = fatfs.getfree("/sd")
    if not data then
        return "", ""
    end
    return math.floor(data.total_kb / 1024) .. " MB", math.floor(data.free_kb / 1024) .. " MB"
end

--[[
读取内存信息

@return string 总内存（如 "3069 KB"）
@return string 剩余内存（如 "2741 KB"）
]]
local function read_mem()
    local total, used = rtos.meminfo("sys")
    return math.floor(total / 1024) .. " KB", math.floor((total - used) / 1024) .. " KB"
end

--[[
读取定位信息：GNSS 卫星定位优先，无解时回退基站/WiFi（LBS）定位

@return number|string 经度，定位失败为 ""
@return number|string 纬度，定位失败为 ""
@return string        定位方式："GNSS" / "LBS" / ""（未定位成功）
]]
local function read_location()
    -- GNSS 卫星定位
    local fix, rmc = gps.getloc()
    if fix then
        return rmc.lng, rmc.lat, "GNSS"
    end
    -- LBS 基站/WiFi 定位（以 is_fix 标志判定，避免初值 0,0 被误判为有效）
    local lbs_fix, lbs_rmc = lbs_util.getloc()
    if lbs_fix then
        return lbs_rmc.lng, lbs_rmc.lat, "LBS"
    end
    return "", "", ""
end

-- 命令处理函数表
local handlers = {}

-- ==================== 一、控制类命令 ====================

--[[ 远程开启录音 ]]
handlers["recording"] = function()
    config.record_ctrl = "recording"
    log.info("device_ctrl", "远程开启录音")
    return "录音已开启"
end

--[[ 远程关闭录音 ]]
handlers["not_recording"] = function()
    config.record_ctrl = "not_recording"
    log.info("device_ctrl", "远程关闭录音")
    return "录音已关闭"
end

--[[ 恢复本地 GPIO22 开关控制录音 ]]
handlers["record_local"] = function()
    config.record_ctrl = -1
    log.info("device_ctrl", "恢复本地 GPIO 开关控制录音")
    return "已恢复本地GPIO开关控制"
end

-- ==================== 二、查询类命令 ====================

--[[ 读取固件版本并上报 ]]
handlers["get_version"] = function()
    local ok, err = excloud.send({
        field(excloud.FIELD_MEANINGS.FIRMWARE_VERSION, excloud.DATA_TYPES.ASCII, read_version())
    }, false)
    if not ok then
        log.error("device_ctrl", "固件版本上报失败", err)
        return "固件版本上报失败"
    end
    return "固件版本已上报"
end

--[[ 读取电池电量并上报 ]]
handlers["get_battery"] = function()
    local ok, err = excloud.send({
        field(excloud.FIELD_MEANINGS.BATTERY_LEVEL, excloud.DATA_TYPES.ASCII, read_battery())
    }, false)
    if not ok then
        log.error("device_ctrl", "电量上报失败", err)
        return "电量上报失败"
    end
    return "电量已上报"
end

--[[ 读取 4G 信号质量并上报 ]]
handlers["get_signal"] = function()
    local ok, err = excloud.send({
        field(excloud.FIELD_MEANINGS.SIGNAL_STRENGTH_4G, excloud.DATA_TYPES.INTEGER, read_signal())
    }, false)
    if not ok then
        log.error("device_ctrl", "信号质量上报失败", err)
        return "信号质量上报失败"
    end
    return "信号质量已上报"
end

--[[ 读取录音文件数量并上报 ]]
handlers["get_record_count"] = function()
    local ok, err = excloud.send({
        field(excloud.FIELD_MEANINGS.BADGE_RECORD_COUNT, excloud.DATA_TYPES.INTEGER, read_record_count())
    }, false)
    if not ok then
        log.error("device_ctrl", "录音数量上报失败", err)
        return "录音数量上报失败"
    end
    return "录音数量已上报"
end

--[[ 读取全部基础信息并聚合上报 ]]
handlers["get_info"] = function()
    local lng, lat, method = read_location()
    local disk_total, disk_free = read_disk()
    local mem_total, mem_free = read_mem()

    local ok, err = excloud.send({
        field(excloud.FIELD_MEANINGS.DEVICE_ID, excloud.DATA_TYPES.ASCII, mobile.imei() or ""),
        field(excloud.FIELD_MEANINGS.FIRMWARE_VERSION, excloud.DATA_TYPES.ASCII, read_version()),
        field(excloud.FIELD_MEANINGS.BATTERY_LEVEL, excloud.DATA_TYPES.ASCII, read_battery()),
        field(excloud.FIELD_MEANINGS.SIGNAL_STRENGTH_4G, excloud.DATA_TYPES.INTEGER, read_signal()),
        field(excloud.FIELD_MEANINGS.SIM_ICCID, excloud.DATA_TYPES.ASCII, mobile.iccid() or ""),
        field(excloud.FIELD_MEANINGS.NETWORK_TYPE, excloud.DATA_TYPES.ASCII, "4G"),
        field(excloud.FIELD_MEANINGS.BOOT_REASON, excloud.DATA_TYPES.ASCII, read_boot_reason()),
        field(excloud.FIELD_MEANINGS.BADGE_TOTAL_DISK, excloud.DATA_TYPES.ASCII, disk_total),
        field(excloud.FIELD_MEANINGS.BADGE_AVAILABLE_DISK, excloud.DATA_TYPES.ASCII, disk_free),
        field(excloud.FIELD_MEANINGS.BADGE_TOTAL_MEM, excloud.DATA_TYPES.ASCII, mem_total),
        field(excloud.FIELD_MEANINGS.BADGE_AVAILABLE_MEM, excloud.DATA_TYPES.ASCII, mem_free),
        field(excloud.FIELD_MEANINGS.BADGE_RECORD_COUNT, excloud.DATA_TYPES.INTEGER, read_record_count()),
        field(excloud.FIELD_MEANINGS.LOCATION_METHOD, excloud.DATA_TYPES.ASCII, method),
        field(excloud.FIELD_MEANINGS.GNSS_LONGITUDE, excloud.DATA_TYPES.ASCII, lng),
        field(excloud.FIELD_MEANINGS.GNSS_LATITUDE, excloud.DATA_TYPES.ASCII, lat),
        field(excloud.FIELD_MEANINGS.TIMESTAMP, excloud.DATA_TYPES.INTEGER, os.time())
    }, false)
    if not ok then
        log.error("device_ctrl", "基础信息上报失败", err)
        return "基础信息上报失败"
    end
    return "基础信息已上报"
end

--[[
处理平台下发的控制命令

@param cmd string 命令字（CONTROL_COMMAND 的 value）
@return string 真实执行结果文本，用于 CONTROL_RESPONSE 回执
@usage
local result = device_ctrl.handle(tlv.value)
]]
function device_ctrl.handle(cmd)
    if cmd == nil then
        log.warn("device_ctrl", "收到空命令")
        return "未知命令: (空)"
    end

    local name = tostring(cmd)

    local handler = handlers[name]
    if not handler then
        log.warn("device_ctrl", "未知命令", name)
        return "未知命令: " .. name
    end

    -- 保护性调用：单个命令异常不影响云平台主任务
    local ok, result = pcall(handler)
    if not ok then
        log.error("device_ctrl", "命令执行异常", name, result)
        return "命令执行失败: " .. name
    end

    log.info("device_ctrl", "命令已执行", name, "结果:", result)
    return result or "命令执行成功"
end

return device_ctrl
