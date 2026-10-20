--[[
@module  aircloud_app
@summary AirCloud 数据上报（excloud）：周期上报 + 精简下行命令
@version 1.0
@date    2026.10.19
@usage
    local aircloud = require "aircloud_app"
    aircloud.init()          -- 网络启动后调用（enabled 且 auth_key 非空才连云）
    aircloud.report_now()
    aircloud.set_cycle(60)
    aircloud.get_status()

配置见 config_*.lua 的 aircloud 表：enabled / auth_key / report_cycle / heartbeat。

上报字段：温度 256、湿度 257、TVOC 258、VBAT 771（mV）、设备ID 798、
版本 1027、网络类型 781、4G CSQ 782、ICCID 783、WiFi RSSI 1295（rssi+100）、
时间戳 1280、在线时长 1284、开机原因 776、开机次数 777、内存 1034。
说明：258 在 excloud 标准表里叫 PARTICULATE，平台侧按 TVOC 使用；
      空气等级不再上报；业务号（BUSINESS_SN，1282）已去掉。
下行命令：cycle:N / report:once / report:on / report:off / status。

关键约束
1. excloud 的 INTEGER/FLOAT 是 uint32 大端，负数/超界会编码成乱数据，push_tlv 统一拦；
2. 空字段不入包（build_tlv 失败会让整包 send 失败）；
3. mobile.* 在 Air8101 走 airlink RPC，无 4G 时会超时，连续失败静默 10 分钟；
4. 心跳载荷不能为空，否则被 excloud 拒绝、平台判离线。
]]

-- 懒加载：enabled=false 时不把 92 KB 的 excloud 读进内存；字面量 require 仍能被烧录合并器识别
local excloud
local function load_lib()
    if not excloud then excloud = require "excloud" end
    return excloud
end

local M = {}

local APP_VERSION = "1.0"

local FSKV_CYCLE   = "aircloud_cycle"
local FSKV_ENABLE  = "aircloud_enable"
local FSKV_BOOTCNT = "aircloud_boot_count"

local DEFAULT_CYCLE   = 180
local MIN_CYCLE       = 5
local MAX_CYCLE       = 86400
local DEFAULT_HEART   = 60
-- 平台侧把 258 定义为 TVOC（excloud 标准表里 258 的名字是 PARTICULATE）
local TVOC_FIELD      = 258
local WIFI_RSSI_FIELD = 1295     -- 自定义：WiFi RSSI + 100

local started          = false
local report_enabled   = true
local report_cycle     = DEFAULT_CYCLE
local heartbeat_sec    = DEFAULT_HEART
local boot_count       = 0
local boot_ts          = os.time()
local report_timer     = nil
local report_busy      = false
local last_ok, last_err, last_time, last_count = false, "", 0, 0

-- 温湿度 / VOC 缓存（订阅而来，避免重复采集）
local temp_cache, hum_cache, voc_cache
local lbs_cache            -- { lat =, lng = } 由 airlbs_app 发布

local function cfg()
    return (_G.project_config or {}).aircloud or {}
end

local function safe_call(name, fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, r1, r2 = pcall(fn, ...)
    if not ok then
        log.debug("aircloud", "调用失败", name, r1)
        return nil, nil
    end
    return r1, r2
end

local function valid_num(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function valid_str(v)
    return type(v) == "string" and #v > 0
end

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

-- ===== 配置 / fskv =====

local function kv_get(k, default)
    local ok, v = pcall(fskv.get, k)
    if not ok then return default end
    return v
end

local function kv_set(k, v)
    return pcall(fskv.set, k, v)
end

local function auth_key()
    local k = cfg().auth_key
    if valid_str(k) then return k end
    return valid_str(_G.PROJECT_KEY) and _G.PROJECT_KEY or ""
end

local function load_settings()
    report_cycle = tonumber(kv_get(FSKV_CYCLE, "")) or tonumber(cfg().report_cycle) or DEFAULT_CYCLE
    report_cycle = math.floor(clamp(report_cycle, MIN_CYCLE, MAX_CYCLE))

    local e = kv_get(FSKV_ENABLE, nil)
    if e == 0 or e == "0" or e == false then
        report_enabled = false
    else
        report_enabled = true
    end

    heartbeat_sec = math.floor(tonumber(cfg().heartbeat) or DEFAULT_HEART)
    if heartbeat_sec < 20 then heartbeat_sec = 20 end
end

-- ===== 设备 ID（与 excloud 鉴权同源：WiFi MAC）=====

local cached_device_id

function M.device_id()
    if cached_device_id then return cached_device_id end
    local mac = safe_call("wlan.getMac", wlan.getMac, nil, true)
    if valid_str(mac) then
        cached_device_id = mac:gsub("[^%w]", ""):upper()
        return cached_device_id
    end
    -- 兜底：有些固件只支持无参调用
    mac = safe_call("wlan.getMac", wlan.getMac)
    if valid_str(mac) then
        cached_device_id = mac:gsub("[^%w]", ""):upper()
        return cached_device_id
    end
    return nil
end

-- ===== mobile.* RPC 熔断（Air8101 外挂 780ER2 才有蜂窝）=====

local mobile_fail_streak, mobile_mute_until = 0, 0
local MOBILE_FAIL_LIMIT, MOBILE_MUTE_SEC = 3, 600

local function mobile_usable()
    return os.time() >= mobile_mute_until
end

local function note_mobile(ok)
    if ok then
        mobile_fail_streak = 0
        return
    end
    mobile_fail_streak = mobile_fail_streak + 1
    if mobile_fail_streak >= MOBILE_FAIL_LIMIT then
        mobile_fail_streak = 0
        mobile_mute_until = os.time() + MOBILE_MUTE_SEC
        log.warn("aircloud", "mobile.* 连续无响应（未接 4G 或外挂未就绪），",
            MOBILE_MUTE_SEC, "秒内跳过蜂窝字段")
    end
end

-- ===== 采集 =====

--- 4G 信号 CSQ（0~31，99/0 视为无效）
local function collect_csq()
    if not mobile_usable() then return nil end
    if type(mobile) == "nil" then return nil end
    local v = safe_call("mobile.csq", mobile.csq)
    note_mobile(valid_num(v))
    if not valid_num(v) or v <= 0 or v >= 99 then return nil end
    return math.floor(v)
end

--- SIM ICCID
local function collect_iccid()
    if not mobile_usable() then return nil end
    if type(mobile) == "nil" then return nil end
    local v = safe_call("mobile.iccid", mobile.iccid)
    note_mobile(valid_str(v))
    if valid_str(v) and v ~= "pc_simulator" then return v end
    return nil
end

--- 当前联网方式：1=WiFi 2=4G 3=以太网（按默认网卡）
local function collect_net_type()
    local ad = socket.dft()
    if ad == socket.LWIP_ETH then return 3 end
    if ad == socket.LWIP_STA then return 1 end
    local gw = socket.LWIP_GP_GW or socket.LWIP_GP
    if ad == gw then return 2 end
    return nil
end

--- WiFi RSSI：上报 rssi+100（uint32 不能表示负数）
local function collect_wifi_rssi()
    local info = safe_call("wlan.getInfo", wlan.getInfo)
    if type(info) ~= "table" then return nil end
    local rssi = info.rssi
    if not valid_num(rssi) or rssi == 0 then return nil end
    if rssi > 0 then rssi = -rssi end
    local shifted = math.floor(rssi) + 100
    if shifted <= 0 then return nil end
    return shifted
end

--- VBAT 主供电电压（mV）：Air8101 内部通道 adc.CH_VBAT，不需要外部 ADC 脚
local vbat_opened = false
local function collect_vbat()
    if not adc or not adc.CH_VBAT then return nil end

    if not vbat_opened then
        local ok = pcall(adc.open, adc.CH_VBAT)
        if not ok then
            log.warn("aircloud", "adc.open(CH_VBAT) 失败，本轮不报电压")
            return nil
        end
        vbat_opened = true
    end

    local ok, mv = pcall(adc.get, adc.CH_VBAT)
    if ok and valid_num(mv) and mv > 0 then return math.floor(mv) end
    return nil
end

local function collect_mem()
    local _, used = pcall(rtos.meminfo, "lua")
    if valid_num(used) and used > 0 then return math.floor(used) end
    local _, u2 = pcall(rtos.meminfo)
    if valid_num(u2) and u2 > 0 then return math.floor(u2) end
    return nil
end

local function collect_boot_reason()
    local v = safe_call("rtos.rebootReason", rtos.rebootReason)
    if valid_num(v) then return math.floor(v) % 100000 end
    return nil
end

-- 数据源订阅
sys.subscribe("TEMP_HUM_UPDATE", function(t, h)
    if valid_num(t) then temp_cache = t end
    if valid_num(h) then hum_cache = h end
end)

sys.subscribe("VOC_UPDATE", function(ppb, ppm, level)
    voc_cache = { ppb = ppb, level = level }
end)

sys.subscribe("AIRLBS_LOCATION", function(lat, lng)
    lbs_cache = { lat = lat, lng = lng }
end)

-- ===== TLV 组装 =====

local function push_tlv(list, field, dtype, value)
    if value == nil then return false end
    if type(value) == "number" then
        if not valid_num(value) then return false end
        local scaled = value
        if dtype == excloud.DATA_TYPES.FLOAT then scaled = value * 1000 end
        if scaled < 0 or scaled >= 4294967296 then
            log.warn("aircloud", "字段", field, "值", value, "超出 uint32 范围，已丢弃")
            return false
        end
    elseif type(value) == "string" then
        if #value == 0 then return false end
    elseif type(value) ~= "boolean" then
        return false
    end

    list[#list + 1] = { field_meaning = field, data_type = dtype, value = value }
    return true
end

local function build_tlvs()
    local DT = excloud.DATA_TYPES
    local FM = excloud.FIELD_MEANINGS
    local list = {}

    local function add(field, dtype, value)
        push_tlv(list, field, dtype, value)
    end

    add(FM.DEVICE_ID, DT.ASCII, M.device_id())
    add(FM.FIRMWARE_VERSION, DT.ASCII, _G.VERSION)
    add(FM.TEMPERATURE, DT.FLOAT, temp_cache)
    add(FM.HUMIDITY, DT.FLOAT, hum_cache)
    add(FM.BATTERY_LEVEL, DT.INTEGER, collect_vbat())    -- VBAT 主供电电压（mV）
    if voc_cache then
        add(TVOC_FIELD, DT.INTEGER, voc_cache.ppb)     -- 258：平台侧按 TVOC 使用
    end
    add(FM.NETWORK_TYPE, DT.INTEGER, collect_net_type())
    add(FM.SIGNAL_STRENGTH_4G, DT.INTEGER, collect_csq())
    add(FM.SIM_ICCID, DT.ASCII, collect_iccid())
    add(WIFI_RSSI_FIELD, DT.INTEGER, collect_wifi_rssi())
    if lbs_cache then
        add(FM.GNSS_LONGITUDE, DT.ASCII, tostring(lbs_cache.lng))
        add(FM.GNSS_LATITUDE, DT.ASCII, tostring(lbs_cache.lat))
    end
    add(FM.TIMESTAMP, DT.INTEGER, os.time())
    add(FM.ONLINE_DURATION, DT.INTEGER, os.time() - boot_ts)
    add(FM.BOOT_REASON, DT.INTEGER, collect_boot_reason())
    add(FM.BOOT_COUNT, DT.INTEGER, boot_count)
    add(FM.LUA_MEM_CURRENT_USED, DT.INTEGER, collect_mem())
    return list
end

-- ===== 上报 =====

local function publish_result(success, count, err)
    sys.publish("AIRCLOUD_REPORT_RESULT", {
        success = success, time = os.time(), count = count or 0, err = err or "",
    })
end

local function do_report(reason)
    if report_busy then
        log.warn("aircloud", "上一轮上报未结束，跳过")
        return false
    end
    report_busy = true

    local st = excloud.status and excloud.status() or nil
    if not st or not st.is_open or not st.is_connected then
        report_busy = false
        last_ok, last_err, last_time = false, "未连接", os.time()
        publish_result(false, 0, "未连接")
        return false
    end

    local ok_build, tlvs = pcall(build_tlvs)
    if not ok_build or type(tlvs) ~= "table" or #tlvs == 0 then
        report_busy = false
        last_ok, last_err = false, "无可用字段"
        log.warn("aircloud", "本轮无可上报字段")
        publish_result(false, 0, "无可用字段")
        return false
    end

    local ok, ret, err = pcall(excloud.send, tlvs, false)
    report_busy = false
    last_time, last_count = os.time(), #tlvs

    if ok and ret ~= false then
        last_ok, last_err = true, ""
        log.info("aircloud", "上报成功", "字段", #tlvs, "原因", reason or "-")
        publish_result(true, #tlvs, "")
        return true
    end

    last_ok, last_err = false, tostring(err or "发送失败")
    log.warn("aircloud", "上报失败:", last_err)
    publish_result(false, #tlvs, last_err)
    return false
end

local function start_timer()
    if report_timer then
        sys.timerStop(report_timer)
        report_timer = nil
    end
    if not started then return end

    report_timer = sys.timerLoopStart(function()
        if report_enabled then
            sys.publish("AIRCLOUD_REPORT_TICK", "timer")
        end
    end, report_cycle * 1000)
    log.info("aircloud", "上报定时器", report_enabled and "已启动" or "已暂停",
        "周期", report_cycle, "秒")
end

-- ===== 下行命令 =====

local function send_response(msg)
    local DT, FM = excloud.DATA_TYPES, excloud.FIELD_MEANINGS
    pcall(excloud.send, {
        { field_meaning = FM.CONTROL_RESPONSE, data_type = DT.ASCII, value = tostring(msg) }
    }, false)
end

local function handle_command(cmd)
    if not valid_str(cmd) then return end
    log.info("aircloud", "收到下行命令:", cmd)

    local cycle_val = cmd:match("^cycle[:=](%d+)$")
    if cycle_val then
        local sec = tonumber(cycle_val)
        if sec and sec >= MIN_CYCLE then
            M.set_cycle(sec)
            send_response("OK cycle=" .. report_cycle)
        else
            send_response("ERR cycle too small, min=" .. MIN_CYCLE)
        end
        return
    end

    if cmd == "report:once" or cmd == "report" then
        sys.publish("AIRCLOUD_REPORT_TICK", "cloud_cmd")
        send_response("OK report triggered")
        return
    end

    local flag = cmd:match("^report[:=](%a+)$")
    if flag then
        if flag == "on" then
            M.set_enable(true)
            send_response("OK report=on")
        elseif flag == "off" then
            M.set_enable(false)
            send_response("OK report=off")
        else
            send_response("ERR unknown report flag")
        end
        return
    end

    if cmd == "status" then
        local st = M.get_status()
        send_response(string.format(
            "OK cycle=%d enable=%s last=%s fields=%d conn=%s auth=%s",
            report_cycle, report_enabled and "on" or "off",
            last_ok and "ok" or (last_err ~= "" and last_err or "none"),
            last_count, tostring(st.connected), tostring(st.authenticated)))
        return
    end

    send_response("ERR unknown cmd: " .. cmd)
end

-- ===== excloud 事件 =====

local function on_event(event, data)
    if event == "connect_result" then
        log.info("aircloud", "连接结果:", data and data.success, data and data.message or "")

    elseif event == "auth_result" then
        log.info("aircloud", "鉴权结果:", data and data.success, data and data.message or "")
        if data and data.success then
            sys.publish("AIRCLOUD_AUTH_OK")
            sys.publish("AIRCLOUD_REPORT_TICK", "auth")     -- 鉴权成功先补一轮
        end

    elseif event == "message" then
        -- 载荷是 { header = {...}, tlvs = {...} }，不是 TLV 数组
        local items = (type(data) == "table" and data.tlvs) or data
        if type(items) ~= "table" then return end
        local FM = excloud.FIELD_MEANINGS
        for _, item in ipairs(items) do
            if type(item) == "table" and item.field == FM.CONTROL_COMMAND then
                handle_command(tostring(item.value or ""))
            end
        end

    elseif event == "disconnect" then
        log.warn("aircloud", "连接断开:", data and data.message or "")
    elseif event == "reconnect_failed" then
        log.error("aircloud", "重连失败:", data and data.message or "")
    elseif event == "send_result" then
        if data and data.success == false then
            log.warn("aircloud", "发送失败:", data.message or data.error_msg or "")
        end
    elseif event == "auth_key_error" then
        log.error("aircloud", "auth_key 无效，请检查 config.aircloud.auth_key")
    end
end

-- ===== 启动 =====

local function run_task()
    -- 等网络（默认网卡拿到 IP）
    while not socket.adapter(socket.dft()) do
        sys.waitUntil("IP_READY", 1000)
    end

    load_settings()
    boot_count = (tonumber(kv_get(FSKV_BOOTCNT, 0)) or 0) + 1
    kv_set(FSKV_BOOTCNT, boot_count)

    local key = auth_key()
    log.info("aircloud", "启动", "设备", M.device_id() or "?", "周期", report_cycle,
        "秒", "开关", report_enabled and "on" or "off", "开机次数", boot_count)

    -- setup（device_type / protocol_version 由库自动处理，不要传）
    -- auth_key 为空时必须传 nil：excloud 内部用 `if not config.auth_key` 判断，
    -- 传 "" 会被当成"已有 key"，鉴权报文变成 "-设备ID-"，平台必然拒绝
    local ok, err = excloud.setup({
        use_getip            = true,
        auth_key             = (key ~= "") and key or nil,
        transport            = "tcp",
        auto_reconnect       = true,
        reconnect_interval   = 10,
        max_reconnect        = 5,
        virtual_phone_number = "10012345678",   -- 仅 PC 模拟器需要
    })
    if not ok then
        log.error("aircloud", "excloud.setup 失败:", err or "")
        started = false
        return
    end

    excloud.on(on_event)

    local open_ok, open_err = excloud.open()
    if not open_ok then
        log.error("aircloud", "excloud.open 失败:", open_err or "")
        started = false
        return
    end

    -- 心跳载荷必须非空，否则 excloud 拒绝发送、平台判离线
    excloud.start_heartbeat(heartbeat_sec, {
        { field_meaning = excloud.FIELD_MEANINGS.DEVICE_ID,
          data_type = excloud.DATA_TYPES.ASCII, value = M.device_id() or "unknown" },
        { field_meaning = excloud.FIELD_MEANINGS.FIRMWARE_VERSION,
          data_type = excloud.DATA_TYPES.ASCII, value = _G.VERSION or APP_VERSION },
    })

    start_timer()

    -- 等鉴权走完再首报
    sys.wait(5000)
    sys.publish("AIRCLOUD_REPORT_TICK", "boot")

    while true do
        local _, reason = sys.waitUntil("AIRCLOUD_REPORT_TICK")
        if report_enabled then
            do_report(reason)
        end
    end
end

-- ===== 对外接口 =====

--- 启动（幂等）：enabled=false 时不连云；auth_key 留空时走 getip 自动获取
function M.init()
    if started then return true end

    if cfg().enabled ~= true then
        log.info("aircloud", "未启用（config.aircloud.enabled=false），不上报")
        return false
    end
    if auth_key() == "" then
        -- 不拦：excloud 会用 device_id 请求 getip 服务，由平台下发 host/port/auth_key
        log.warn("aircloud", "未配置 auth_key，改由 getip 服务自动获取（要求平台已登记这台设备）")
    end

    started = true
    local ok, err = pcall(load_lib)
    if not ok then
        log.error("aircloud", "excloud 加载失败:", err or "")
        started = false
        return false
    end
    sys.taskInit(run_task)
    return true
end

function M.report_now()
    if not started then return false end
    sys.publish("AIRCLOUD_REPORT_TICK", "manual")
    return true
end

--- 改上报周期（秒），写 fskv 并立即重排定时器
function M.set_cycle(seconds)
    seconds = tonumber(seconds)
    if not seconds then return false end
    report_cycle = math.floor(clamp(seconds, MIN_CYCLE, MAX_CYCLE))
    kv_set(FSKV_CYCLE, report_cycle)
    start_timer()
    log.info("aircloud", "上报周期改为", report_cycle, "秒")
    return true
end

--- 开关上报（写 fskv，重启后保持）
function M.set_enable(on)
    report_enabled = on and true or false
    kv_set(FSKV_ENABLE, report_enabled and 1 or 0)
    start_timer()
    if report_enabled then
        sys.publish("AIRCLOUD_REPORT_TICK", "enable")
    end
    log.info("aircloud", "上报开关", report_enabled and "on" or "off")
    return true
end

function M.get_status()
    local st = (excloud and excloud.status and excloud.status()) or {}
    return {
        enabled       = report_enabled,
        cycle         = report_cycle,
        heartbeat     = heartbeat_sec,
        connected     = st.is_connected and true or false,
        authenticated = st.is_authenticated and true or false,
        is_open       = st.is_open and true or false,
        last_ok       = last_ok,
        last_time     = last_time,
        last_err      = last_err,
        last_count    = last_count,
        boot_count    = boot_count,
        device_id     = M.device_id(),
        version       = APP_VERSION,
    }
end

-- ===== 事件（供页面/其它模块调用）=====

sys.subscribe("AIRCLOUD_SET_CYCLE", function(sec) M.set_cycle(sec) end)
sys.subscribe("AIRCLOUD_SET_ENABLE", function(on) M.set_enable(on) end)
sys.subscribe("AIRCLOUD_REPORT_NOW", function() M.report_now() end)
sys.subscribe("AIRCLOUD_GET_STATUS", function()
    sys.publish("AIRCLOUD_STATUS_RESP", M.get_status())
end)

log.info("aircloud", "模块已加载 v" .. APP_VERSION)

return M
