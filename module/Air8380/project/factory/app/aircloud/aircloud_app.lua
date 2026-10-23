--[[
@module  aircloud_app
@summary AirCloud 数据上报 + 运维日志 + 下行命令
@version 1.0
@date    2026.10.20

要点（与 Air8300 出厂固件保持一致的做法）：
1. AirCloud 用 use_getip 自动认证，**不需要 project_key**，上电联网即连；
   project_key 只给 FOTA 用，与本模块无关；
2. excloud 回调由 C 层直接调用，不在协程内 —— 回调里禁止 sys.wait，
   需要耗时动作（重启、改配置）一律 sys.taskInit / sys.timerStart 投递；
3. 上报字段做有效性过滤：excloud.build_tlv 遇到空字段会整包失败，
   未插卡时的空 ICCID、未同步的 CPU 温度都要跳过；
4. 每次上报成功 sys.publish("FEED_NETWORK_WATCHDOG")，给网络看门狗喂狗。

上报字段（沿用 Air8300 已登记的数据点）：
  782  4G 信号强度 (INTEGER)
  783  SIM ICCID  (ASCII)
  263  CPU 温度   (INTEGER)
  799  VBAT 电压  (INTEGER)
  269  当前链路   (ASCII, 自定义字段，需在平台登记为"当前链路"字符串)
]]

local app_config = require "app_config"
local status = require "status"
local storage = require "storage"
local net_drv = require "net_drv"

local excloud = require "excloud"

local M = {}

local ACTIVE_LINK_FIELD = 269   -- 自定义字段：当前生效链路（Ethernet / WiFi / 4G / 无）

-- 定位结果（由 airlbs_app 发布）
local lat, lng = nil, nil
sys.subscribe("Airlbs_LOCATION_UPDATE", function(la, ln)
    lat, lng = la, ln
    log.info("aircloud", "定位更新", tostring(la), tostring(ln))
end)

local function mtn_log(tag, ...)
    local ok, err = pcall(excloud.mtn_log, tag, ...)
    if not ok then log.warn("aircloud", "运维日志写入失败:", err) end
end

-- 过滤无效字段，避免整包被丢弃
local function filter_valid(list, tag)
    local out = {}
    local DT = excloud.DATA_TYPES
    for _, item in ipairs(list) do
        local t, v = item.data_type, item.value
        local bad
        if t == nil or v == nil then
            bad = "nil"
        elseif t == DT.ASCII or t == DT.UNICODE or t == DT.BINARY then
            if type(v) ~= "string" or #v == 0 then bad = "空字符串" end
        elseif t == DT.INTEGER or t == DT.FLOAT then
            if type(v) ~= "number" then bad = "非数字" end
        end
        if bad then
            log.warn("aircloud", tag, "跳过字段", item.field_meaning, bad)
        else
            out[#out + 1] = item
        end
    end
    return out
end

-- ==================== 下行命令 ====================
-- 只做"查询"和"投递式动作"，不在 C 回调里 sys.wait
-- 解析下行载荷：标准 JSON 优先，同时兼容「命令名{参数}」简写（如 read_flash{"bytes":50}）
local function parse_command(value)
    local s = tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if s == "" then return nil end
    local ok, cmd = pcall(json.decode, s)
    if ok and type(cmd) == "table" and cmd.type then return cmd end
    local name, rest = s:match("^(%a[%w_%-]*)%s*(.*)$")
    if not name then return nil end
    if rest == "" then return { type = name } end
    local ok2, arg = pcall(json.decode, rest)
    if ok2 and type(arg) == "table" then
        arg.type = arg.type or name
        return arg
    end
    return nil
end

local function handle_command(value)
    local cmd = parse_command(value)
    if not cmd then
        log.info("aircloud", "忽略无法解析的下行:", tostring(value):sub(1, 64))
        return
    end
    log.info("aircloud", "收到命令:", cmd.type)
    mtn_log("aircloud", "收到命令:" .. tostring(cmd.type))

    local resp = {}
    if cmd.type == "read_status" then
        resp = status.snapshot()
    elseif cmd.type == "read_csq" then
        resp.csq = status.network().csq
    elseif cmd.type == "read_imei" then
        resp.imei = status.device().imei
    elseif cmd.type == "read_iccid" then
        resp.iccid = status.device().iccid
    elseif cmd.type == "read_version" then
        resp.version = VERSION
        resp.core = status.device().core
    elseif cmd.type == "read_link" then
        resp.active = status.network().active
    elseif cmd.type == "read_location" then
        resp.lat = lat
        resp.lng = lng
    elseif cmd.type == "read_flash" then
        -- 读板载 Flash 里保存的固定值
        local val = storage.get_fixed()
        if val then
            resp.val = val
            resp.len = #val
        else
            resp.val = ""
            resp.err = storage.is_mounted() and "fixed_missing" or "flash_not_mounted"
        end
    elseif cmd.type == "set_wifi" then
        -- 改 WiFi 要重建网络，投递到任务里执行
        sys.taskInit(function()
            app_config.save({ wifi_ssid = cmd.ssid, wifi_pwd = cmd.pwd })
        end)
        resp.ok = true
    elseif cmd.type == "sync_time" then
        socket.sntp()
        resp.ok = true
    elseif cmd.type == "reboot" then
        sys.timerStart(rtos.reboot, 2000)
        resp.ok = true
    else
        resp = { error = "未知命令", cmd = tostring(cmd.type) }
    end

    local tlvs = filter_valid({
        { field_meaning = excloud.FIELD_MEANINGS.CONTROL_RESPONSE,
          data_type = excloud.DATA_TYPES.ASCII,
          value = json.encode(resp) },
    }, "命令应答")
    if #tlvs > 0 then
        pcall(excloud.send, tlvs, false)
    end
end

local function on_event(event, data)
    if event == "connect_result" then
        if data.success then
            log.info("aircloud", "连接成功")
            mtn_log("aircloud", "连接成功")
        else
            log.warn("aircloud", "连接失败:", data.error)
            mtn_log("aircloud", "连接失败:" .. tostring(data.error))
        end
    elseif event == "auth_result" then
        if data.success then
            log.info("aircloud", "认证成功")
            mtn_log("aircloud", "认证成功")
        else
            log.warn("aircloud", "认证失败:", data.message)
            mtn_log("aircloud", "认证失败:" .. tostring(data.message))
        end
    elseif event == "message" then
        for _, tlv in ipairs(data.tlvs or {}) do
            log.info("aircloud", "下行 TLV", tlv.field, string.sub(tostring(tlv.value), 1, 128))
            if tlv.field == excloud.FIELD_MEANINGS.CONTROL_COMMAND
                or tlv.field == excloud.FIELD_MEANINGS.IRTU_DOWN
                or tlv.field == excloud.FIELD_MEANINGS.RANDOM_DATA then
                handle_command(tlv.value)
            end
        end
    elseif event == "disconnect" then
        log.warn("aircloud", "与服务器断开")
        mtn_log("aircloud", "与服务器断开")
    elseif event == "reconnect_failed" then
        log.warn("aircloud", "重连失败，已尝试 " .. tostring(data.count) .. " 次")
    elseif event == "send_result" then
        if not data.success then
            log.warn("aircloud", "发送失败:", data.error_msg)
        end
    end
end

-- ==================== 主任务 ====================
local function cloud_task()
    local c = app_config.load()
    if c.cloud_enabled == false then
        log.info("aircloud", "上云已关闭，跳过")
        return
    end

    -- 等任意一条链路拿到 IP
    while not socket.adapter(socket.dft()) do
        sys.waitUntil("IP_READY", 2000)
    end
    sys.wait(1000)

    excloud.on(on_event)

    local ok, err = excloud.setup({
        use_getip = true,
        transport = "tcp",
        auto_reconnect = true,
        reconnect_interval = 10,
        max_reconnect = 5,
        timeout = 30,
        mtn_log_enabled = true,
        mtn_log_blocks = 4,
        mtn_log_write_way = excloud.MTN_LOG_ADD_WRITE,
        aircloud_mtn_log_enabled = true,
    })
    if not ok then
        log.error("aircloud", "excloud.setup 失败:", err)
        return
    end
    local open_ok, open_err = excloud.open()
    if not open_ok then
        log.error("aircloud", "excloud.open 失败:", open_err)
        return
    end
    log.info("aircloud", "已连接 AirCloud")
    mtn_log("aircloud", "上线 " .. tostring(VERSION))
    storage.log("aircloud", "已连接 AirCloud")

    local count = 0
    while true do
        local interval = tonumber(app_config.load().report_interval) or 60
        if interval < 10 then interval = 10 end

        local d = status.device()
        local n = status.network()
        local s = status.system()
        count = count + 1

        local tlvs = filter_valid({
            { field_meaning = excloud.FIELD_MEANINGS.SIGNAL_STRENGTH_4G,
              data_type = excloud.DATA_TYPES.INTEGER, value = n.csq or 0 },
            { field_meaning = excloud.FIELD_MEANINGS.SIM_ICCID,
              data_type = excloud.DATA_TYPES.ASCII, value = d.iccid },
            { field_meaning = excloud.FIELD_MEANINGS.ENV_TEMPERATURE,
              data_type = excloud.DATA_TYPES.INTEGER, value = s.cpu_temp and math.floor(s.cpu_temp) or nil },
            { field_meaning = excloud.FIELD_MEANINGS.VOLTAGE,
              data_type = excloud.DATA_TYPES.INTEGER, value = s.vbat and math.floor(s.vbat) or nil },
            { field_meaning = ACTIVE_LINK_FIELD,
              data_type = excloud.DATA_TYPES.ASCII, value = tostring(n.active or "无") },
            -- 经纬度：未定位时为空串，filter_valid 会跳过，不影响整包
            { field_meaning = excloud.FIELD_MEANINGS.GNSS_LATITUDE,
              data_type = excloud.DATA_TYPES.ASCII, value = lat or "" },
            { field_meaning = excloud.FIELD_MEANINGS.GNSS_LONGITUDE,
              data_type = excloud.DATA_TYPES.ASCII, value = lng or "" },
        }, "周期上报")

        if #tlvs == 0 then
            log.warn("aircloud", "本轮无可上报字段")
        else
            log.info("aircloud", "周期上报", #tlvs, "个字段", "链路", tostring(n.active), "CSQ", tostring(n.csq))
            local send_ok, send_err = excloud.send(tlvs, false)
            if send_ok then
                sys.publish("FEED_NETWORK_WATCHDOG")
                if count % 10 == 1 then
                    mtn_log("aircloud", "周期上报正常，累计 " .. count)
                end
            else
                log.warn("aircloud", "上报失败:", send_err)
            end
        end

        sys.wait(interval * 1000)
    end
end

sys.taskInit(cloud_task)

function M.get_state()
    return { enabled = app_config.load().cloud_enabled }
end

return M
