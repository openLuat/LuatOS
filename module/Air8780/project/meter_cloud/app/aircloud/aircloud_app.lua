-- @module  aircloud_app
-- @summary AirCloud 数据上报（电表数据 TLV）
-- @version 001.000.000
-- @date    2026.10.26
-- @author  OpenLuat
-- @BSD License
--[[
职责：
1. 联网成功后初始化 excloud，连接 iot.openluat.com（AirCloud）
2. 周期性把 meter_app 的采集结果组 TLV 上报（默认 60s，可远程改）
3. 处理下行命令（CONTROL_COMMAND tag 19，ASCII），并用 CONTROL_RESPONSE（tag 20）应答

下行命令：
  cycle:秒数                 修改上报周期（5~86400s）
  report:now                 立即上报一次
  alarm:on / alarm:off       启用/关闭越限报警
  {"type":"cycle","value":N} JSON 写法，同上
  {"type":"alarm","hi_u":250,"lo_u":180,"hi_i":10,"hi_p":50,"hi_f":50.5,"lo_f":49.5,"hys":2,"enable":1}
                             设置越限报警阈值（只更新传入字段，掉电保存）
  {"type":"alarm_get"}       查询当前阈值与报警状态

上报字段补充：1313 报警位图（bit0 电压/bit1 电流/bit2 功率/bit3 频率），
              1314 报警描述（ASCII，如 "OV,OC"）

Web 端配套：web/index.html（实时/历史数据查看 + 命令下发）。

TLV 字段（电表数据用自定义段 1300~1311，FLOAT = 值×1000 定点编码，
与 web/index.html 的 TAGMAP 一一对应）：
  1300 UA A相电压(V)   1301 UB   1302 UC
  1303 IA A相电流(A)   1304 IB   1305 IC
  1306 P 有功功率(kW)  1307 Q(kvar)  1308 S(kVA)
  1309 PF 功率因数     1310 F 频率(Hz)  1311 EP 正向有功电能(kWh)
标准字段：782 信号(4G)、1280 时间戳；
自定义字段 1293/1294 = 设备ID/项目名（沿用 factory 约定，
避开 783 SIM_ICCID 等标准字段语义）。
注意 FLOAT 为无符号定点编码，负值（如发电反送的 Q）统一钳到 0 再上报。
]]

local excloud   = require "excloud"
local meter_app = require "meter_app"
local alarm_app = require "alarm_app"

-- ==================== 电表 TLV 字段定义 ====================
local METER_TAGS = {
    { tag = 1300, key = "ua" }, { tag = 1301, key = "ub" }, { tag = 1302, key = "uc" },
    { tag = 1303, key = "ia" }, { tag = 1304, key = "ib" }, { tag = 1305, key = "ic" },
    { tag = 1306, key = "p"  }, { tag = 1307, key = "q"  }, { tag = 1308, key = "s"  },
    { tag = 1309, key = "pf" }, { tag = 1310, key = "f"  }, { tag = 1311, key = "ep" },
}

-- ==================== 状态 ====================
local report_cycle = 60          -- 上报周期 s

-- ==================== 工具函数 ====================
local function get_device_id()
    local id = hmeta.devid()
    if id and id ~= "" then return id end
    if mcu and mcu.unique_id then return tostring(mcu.unique_id()) end
    return "unknown"
end

local function add_float(list, tag, v)
    -- FLOAT 为 ×1000 无符号定点编码，负值钳到 0
    if type(v) ~= "number" then return end
    if v < 0 then v = 0 end
    table.insert(list, { field_meaning = tag, data_type = excloud.DATA_TYPES.FLOAT, value = v })
end

local function add_int(list, tag, v)
    if type(v) ~= "number" then return end
    table.insert(list, { field_meaning = tag, data_type = excloud.DATA_TYPES.INTEGER, value = math.floor(v) })
end

local function add_ascii(list, tag, s)
    if type(s) ~= "string" or s == "" then return end
    table.insert(list, { field_meaning = tag, data_type = excloud.DATA_TYPES.ASCII, value = s })
end

-- ==================== TLV 组包 ====================
local function build_meter_tlv()
    local d = meter_app.get_data()
    local list = {}

    -- 信号强度
    add_int(list, excloud.FIELD_MEANINGS.SIGNAL_STRENGTH_4G, (mobile and mobile.csq and mobile.csq()) or 0)
    -- 设备ID / 项目名（自定义字段 1293/1294，沿用 factory 约定）
    add_ascii(list, 1293, get_device_id())
    add_ascii(list, 1294, tostring(PROJECT or ""))
    -- 时间戳
    add_int(list, excloud.FIELD_MEANINGS.TIMESTAMP, os.time())
    -- 板级：供电电压（ADC2，最大 36V，mV → V；tag 1312 与 web/index.html 对齐）
    local hwd = meter_app.get_hw_data and meter_app.get_hw_data()
    if hwd and hwd.vbat and hwd.vbat > 0 then add_float(list, 1312, hwd.vbat / 1000) end
    -- 越限报警：1313 位图（bit0 电压 / bit1 电流 / bit2 功率 / bit3 频率），1314 描述
    local al = alarm_app.get()
    add_int(list, 1313, al.bitmap or 0)
    if al.text and al.text ~= "" then add_ascii(list, 1314, al.text) end

    -- 电表数据（离线时只报基础字段，便于 Web 端看设备在线状态）
    if d and d.online then
        for _, f in ipairs(METER_TAGS) do
            add_float(list, f.tag, d[f.key])
        end
    else
        log.warn("cloud", "电表离线，本次仅上报心跳基础字段")
    end

    log.info("cloud", "上报TLV字段数", #list)
    return list
end

local function report_once()
    local status = excloud.status()
    if not status or not status.is_connected then
        log.warn("cloud", "未连接云端，跳过上报")
        return
    end
    local tlv = build_meter_tlv()
    if #tlv == 0 then return end
    local ok, err_msg = excloud.send(tlv, false)
    if ok then
        log.info("cloud", "数据上报成功")
    else
        log.error("cloud", "数据上报失败:", err_msg)
    end
end

-- ==================== 下行命令 ====================
local function send_response(msg)
    excloud.send({
        {
            field_meaning = excloud.FIELD_MEANINGS.CONTROL_RESPONSE,
            data_type     = excloud.DATA_TYPES.ASCII,
            value         = msg,
        }
    }, false)
end

-- JSON 命令：{"type":"cycle","value":N} / {"type":"report","value":1}
local function handle_json_command(data)
    local ok, j = pcall(json.decode, data)
    if not ok or type(j) ~= "table" then
        return string.format('{"code":1,"type":"unknown","value":"%s"}', tostring(data))
    end
    local cmd, v = j.type, tonumber(j.value)
    if cmd == "cycle" and v then
        if v >= 5 and v <= 86400 then
            report_cycle = v
            log.info("cloud", "上报周期改为", v, "s")
            return string.format('{"code":0,"type":"cycle","value":%d}', v)
        end
        return '{"code":1,"type":"cycle","value":"out of range 5~86400"}'
    elseif cmd == "report" then
        sys.publish("REPORT_NOW")
        return '{"code":0,"type":"report","value":1}'
    elseif cmd == "alarm" then
        return alarm_app.set(j)         -- 增量更新报警阈值，字段见 alarm_app
    elseif cmd == "alarm_get" then
        return alarm_app.get_json()     -- 查询当前阈值与报警状态
    end
    return string.format('{"code":1,"type":"%s","value":"unknown cmd"}', tostring(cmd))
end

-- 文本命令：cycle:120 / report:now
local function handle_text_command(data)
    local sw = string.match(data, "^alarm:%s*(%a+)$")
    if sw then
        if sw == "on" then return alarm_app.enable(true) end
        if sw == "off" then return alarm_app.enable(false) end
        return "alarm:on|off"
    end
    local n = string.match(data, "^cycle:%s*(%d+)$")
    if n then
        n = tonumber(n)
        if n >= 5 and n <= 86400 then
            report_cycle = n
            log.info("cloud", "上报周期改为", n, "s")
            return string.format("cycle:%d", n)
        end
        return "cycle out of range 5~86400"
    elseif string.match(data, "^report:%s*now$") then
        sys.publish("REPORT_NOW")
        return "report:now"
    end
    return string.format("unknown cmd:%s", data)
end

-- ==================== excloud 事件 ====================
local function on_excloud_event(event, data)
    log.info("cloud", event, json.encode(data))

    if event == "connect_result" then
        if data.success then
            log.info("cloud", "连接成功")
            sys.publish("aircloud_connected")
        else
            log.warn("cloud", "连接失败:", data.error)
        end
    elseif event == "auth_result" then
        log.info("cloud", data.success and "认证成功" or ("认证失败:" .. tostring(data.message)))
    elseif event == "message" then
        for _, tlv in ipairs(data.tlvs or {}) do
            if tlv.field == excloud.FIELD_MEANINGS.CONTROL_COMMAND then
                local cmd = tostring(tlv.value or "")
                log.info("cloud", "下行命令:", cmd)
                local resp
                if string.sub(cmd, 1, 1) == "{" then
                    resp = handle_json_command(cmd)
                else
                    resp = handle_text_command(cmd)
                end
                send_response(resp)
            end
        end
    elseif event == "disconnect" then
        log.warn("cloud", "与服务器断开连接")
    elseif event == "reconnect_failed" then
        log.warn("cloud", "重连失败，已尝试", data.count, "次")
    elseif event == "send_result" then
        if not data.success then
            log.warn("cloud", "发送失败:", data.error_msg)
        end
    end
end

-- ==================== 主任务 ====================
sys.taskInit(function()
    -- 等待默认网卡就绪
    while not socket.adapter(socket.dft()) do
        log.warn("cloud", "wait IP_READY", socket.dft())
        sys.waitUntil("IP_READY", 1000)
    end

    local device_type
    if rtos.bsp() == "PC" then
        device_type = 9
    elseif rtos.bsp() ~= "Air8101" then
        device_type = 1
    else
        device_type = 2
    end

    local ok, err_msg = excloud.setup({
        use_getip             = true,
        device_type           = device_type,
        auth_key              = PROJECT_KEY,
        transport             = "tcp",
        auto_reconnect        = true,
        reconnect_interval    = 10,
        max_reconnect         = 5,
        virtual_phone_number  = "10012345678",
    })
    if not ok then
        log.error("cloud", "excloud初始化失败:", err_msg)
        return
    end

    excloud.on(on_excloud_event)

    ok, err_msg = excloud.open()
    if not ok then
        log.error("cloud", "开启excloud服务失败:", err_msg)
        return
    end
    excloud.start_heartbeat()
    log.info("cloud", "AirCloud 已开启，上报周期", report_cycle, "s")

    -- 启动电表采集（meter_app 周期采集，这里取最新数据上报）
    meter_app.start()

    -- 主循环：周期上报（report:now 命令可提前唤醒）
    while true do
        sys.waitUntil("REPORT_NOW", report_cycle * 1000)
        report_once()
    end
end)
