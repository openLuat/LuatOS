--[[
@module  aircloud_data
@summary AirCloud平台数据上报与命令处理模块
@version 1.0
@date    2026.09.24
@author  黄何
@usage
本文件为AirCloud数据处理模块，负责定时通过 excloud.send 上报设备数据到 AirCloud 平台，
并处理平台下发的控制命令（4路继电器开/关/全开/全关/回读、三色LED红/绿/蓝/灭等）。

下行通道：同时兼容 Tag 19（控制命令）、Tag 21（iRTU下行指令）、Tag 1281（自定义下行消息），
         平台上任一入口下发均可收到；载荷支持 JSON（如 {"type":"led_set","color":"red"}）
         与文本短命令（如 led:red、led:off、led_read、relay:open,0）。
         收到每条下行 TLV 都会打印 field/type/value 诊断日志，便于确认平台实际下发的通道与载荷。

数据来源（事件订阅，零重复采集）：
  - 定位经纬度 → 订阅 airlbs_app 发布的 Airlbs_LOCATION_UPDATE
  - 环境温湿度 → 订阅 tcp_modbus_master 发布的 TCP_TEMP_HUMIDITY_UPDATE
  - 4路继电器状态 → 订阅 relay_ctrl 发布的 RELAY_STATUS_UPDATE
  - 系统数据(CPU/VBAT/CSQ/ICCID) → 发送时实时读取（系统级API）

上报字段：
  - 4G信号强度 (782, INTEGER)
  - SIM ICCID (783, ASCII)
  - 环境温度 (256, FLOAT)
  - 环境湿度 (257, FLOAT)
  - CPU温度 (263, INTEGER)
  - VBAT电压 (799, INTEGER)
  - GNSS经度 (512, ASCII)
  - GNSS纬度 (513, ASCII)
  - 继电器状态 (268, ASCII，逗号分隔，如 "1,1,0,0"，'1'=吸合 '0'=断开)

运维日志：已启用 AirCloud 运维日志（4 个 block、追加写入方式），
         在连接、认证、初始化、命令执行、周期上报等关键业务点记录日志，便于定位运行状态。

本文件没有对外接口，直接在main.lua中require "aircloud_data"就可以加载运行；
]]

local excloud = require "excloud"
local relay_ctrl = require "relay_ctrl"
local led = require "led"

-- 继电器状态 tag：自定义字段 268，承载继电器各路状态（逗号分隔字符串）。
-- 选用理由：268 属协议"传感采集类"区间（256~511）；excloud 库在该区间仅收录 256~265，
--           266 及以后库中未定义，268 为空闲编号，语义独立，平台可命名为"继电器状态"。
-- 协议依据：上行业务载荷合法区间为 256~2047，268 在区间内；
--           excloud.build_tlv 仅做非空校验并按 field % 0x1000 编码，无字段白名单，
--           因此可直接发送库中未定义的编号。
-- 使用前提：需在 AirCloud 平台预先登记数据点（名称"继电器状态"、编号 268、类型"字符串"）。
-- 数据格式：ASCII 字符串，各通道状态以英文逗号分隔（从左到右依次为继电器1~继电器4），
--           '1'=吸合、'0'=断开。例：4 路 "1,1,0,0"（继电器1、继电器2 吸合）。
local RELAY_STATUS_FIELD = 268

-- 将继电器状态数组编码为逗号分隔的 ASCII 字符串
-- @param state table 继电器状态数组（1-based，元素 0/1）
-- @return string 形如 "1,1,0,0" 的字符串，字段个数 = 当前路数
local function relay_state_to_string(state)
    local n = relay_ctrl.get_channel_count()
    local buf = {}
    for i = 1, n do
        buf[i] = (state and state[i] == 1) and "1" or "0"
    end
    return table.concat(buf, ",")
end

-- ==================== 上报字段有效性过滤 ====================
-- 背景：excloud.build_tlv 只要遇到一个"无法编码"的字段就直接判定失败，
--       而 excloud.send 遍历 tlv_list 时任一字段构建失败就整包返回 false，
--       结果是该轮全部数据（含温湿度、继电器状态等正常字段）一起被丢弃。
-- 触发条件：
--   1) ASCII / UNICODE / BINARY 类型字段值为 nil 或空字符串
--      —— 典型：GNSS 尚未定位时经纬度为空串、SIM 未就绪时 ICCID 为空串；
--   2) INTEGER / FLOAT 类型字段值不是 number（如 nil 或字符串）。
-- 对策：组包后统一过滤无效字段，保证有效数据照常上报；被跳过字段打印日志便于排查。
-- @param list table 待发送的 TLV 数组
-- @param tag  string 日志标签（区分调用点，如"周期上报"/"命令应答"）
-- @return table 过滤后的 TLV 数组（可能为空表，调用方需判空）
local function filter_valid_tlvs(list, tag)
    local out = {}
    local DT = excloud.DATA_TYPES
    for _, item in ipairs(list) do
        local t, v = item.data_type, item.value
        local reason
        if t == nil or v == nil then
            reason = "值为空(nil)"
        elseif t == DT.ASCII or t == DT.UNICODE or t == DT.BINARY then
            if type(v) ~= "string" or #v == 0 then
                reason = "字符串为空"
            end
        elseif t == DT.INTEGER or t == DT.FLOAT then
            if type(v) ~= "number" then
                reason = "非数字(" .. type(v) .. ")"
            end
        end
        if reason then
            log.warn("aircloud_data", tag, "跳过无效字段 field:", item.field_meaning,
                "type:", t, "原因:", reason, "值:", tostring(v))
        else
            out[#out + 1] = item
        end
    end
    return out
end

-- 运维日志辅助函数：写入运维日志（通过 excloud.mtn_log）
-- @param tag string 日志标签
-- @param ... 日志内容
local function mtn_log(tag, ...)
    local ok, err = pcall(excloud.mtn_log, tag, ...)
    if not ok then
        log.warn("aircloud_data", "运维日志写入失败:", err)
    end
end

-- 经纬度（订阅 airlbs_app）
local lat, lng = nil, nil
local function on_location_update(new_lat, new_lng)
    lat = new_lat
    lng = new_lng
end
sys.subscribe("Airlbs_LOCATION_UPDATE", on_location_update)

-- 环境温湿度（订阅 tcp_modbus_master 采集的以太网温湿度变送器数据）
local rtu_temp, rtu_hum = nil, nil
local function on_temp_humidity_update(temp, humi)
    rtu_temp = temp
    rtu_hum = humi
end
sys.subscribe("TCP_TEMP_HUMIDITY_UPDATE", on_temp_humidity_update)

-- 4路继电器状态（订阅 relay_ctrl）
local relay_state = {}
for i = 1, relay_ctrl.get_channel_count() do relay_state[i] = 0 end
local function on_relay_status_update(new_state)
    if type(new_state) ~= "table" then return end
    for i = 1, #relay_state do
        relay_state[i] = new_state[i] or 0
    end
end
sys.subscribe("RELAY_STATUS_UPDATE", on_relay_status_update)

-- 文本短命令解析（兼容 iRTU 下行指令与平台文本输入框的常见写法）
-- 支持示例：
--   led:red / led,red / led_set,red / led#blue      → 三色LED（三路互斥，一次只亮一路）
--   led:off / led_off                               → 全灭
--   led / led_read                                  → 回读LED当前状态
--   relay:open,0 / relay:close,1 / relay:toggle,2   → 继电器开/关/翻转（通道号 0~3）
--   relay:read / relay_read                         → 回读继电器状态
--   read_all                                        → 读取全部数据
-- @param value string 文本命令
-- @return table|nil 解析成功返回含 type 字段的命令表，无法识别返回 nil
local function parse_text_command(value)
    local s = tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if #s == 0 then return nil end

    -- 带参数形式："头:参数" / "头,参数" / "头#参数"
    local head, arg = s:match("^([%a_]+)[:,#](.+)$")
    if head then
        head = head:lower()
        arg = arg:gsub("^%s+", ""):gsub("%s+$", "")
        if head == "led" or head == "led_set" then
            return { type = "led_set", color = arg }
        elseif head == "relay" then
            local act, ch = arg:match("^([%a_]+)%s*,?%s*(%d*)$")
            if act == "open" then return { type = "relay_open", channel = tonumber(ch) } end
            if act == "close" then return { type = "relay_close", channel = tonumber(ch) } end
            if act == "toggle" then return { type = "relay_toggle", channel = tonumber(ch) } end
            if act == "read" then return { type = "relay_read" } end
            return nil
        end
        return nil
    end

    -- 无参数短命令
    local single = s:lower()
    if single == "led_off" then return { type = "led_off" } end
    if single == "led_read" or single == "led" then return { type = "led_read" } end
    if single == "relay_read" then return { type = "relay_read" } end
    if single == "read_all" then return { type = "read_all" } end
    return nil
end

-- 云端控制命令处理
-- @param value 云端下发的命令内容（JSON 字符串或文本短命令）
local function handle_control_command(value)
    local ok, cmd = pcall(json.decode, tostring(value))
    if not ok or type(cmd) ~= "table" or not cmd.type then
        cmd = parse_text_command(value)     -- JSON 解析失败时，按文本短命令兜底解析
    end
    if type(cmd) ~= "table" or not cmd.type then
        log.info("aircloud", "无效命令:", tostring(value))
        mtn_log("aircloud", "无效命令:" .. string.sub(tostring(value), 1, 64))
        return
    end
    log.info("aircloud", "收到命令:", cmd.type)
    mtn_log("aircloud", "收到命令:" .. tostring(cmd.type))

    local resp = {}
    if cmd.type == "read_all" then
        adc.open(adc.CH_CPU); resp.cpu_temp = adc.get(adc.CH_CPU) / 1000; adc.close(adc.CH_CPU)
        adc.open(adc.CH_VBAT); resp.vbat = adc.get(adc.CH_VBAT) / 1000; adc.close(adc.CH_VBAT)
        resp.temperature = rtu_temp or 0; resp.humidity = rtu_hum or 0
        resp.latitude = lat or ""; resp.longitude = lng or ""
        resp.csq = mobile.csq() or 0; resp.imei = mobile.imei() or ""; resp.iccid = mobile.iccid() or ""
        resp.timestamp = os.time()
        resp.relay = relay_ctrl.get_state()
    elseif cmd.type == "read_temp" then
        resp.temperature = rtu_temp or 0
    elseif cmd.type == "read_humi" then
        resp.humidity = rtu_hum or 0
    elseif cmd.type == "read_vbat" then
        adc.open(adc.CH_VBAT); resp.vbat = adc.get(adc.CH_VBAT) / 1000; adc.close(adc.CH_VBAT)
    elseif cmd.type == "read_cpu" then
        adc.open(adc.CH_CPU); resp.cpu_temp = adc.get(adc.CH_CPU) / 1000; adc.close(adc.CH_CPU)
    elseif cmd.type == "read_lat" then
        resp.latitude = lat or ""
    elseif cmd.type == "read_lng" then
        resp.longitude = lng or ""
    elseif cmd.type == "read_csq" then
        resp.csq = mobile.csq() or 0
    elseif cmd.type == "read_imei" then
        resp.imei = mobile.imei() or ""
    elseif cmd.type == "read_iccid" then
        resp.iccid = mobile.iccid() or ""
    elseif cmd.type == "read_time" then
        resp.timestamp = os.time()

    -- 继电器控制命令（channel 为 0~3，对应继电器1~继电器4）
    -- 【关键】excloud 消息回调由 C 层直接调用，不在协程中，不能直接执行会 sys.wait 的 Modbus 事务，
    --        否则会触发 "attempt to yield from outside a coroutine" 导致 Lua VM 退出、设备重启。
    --        此处统一走 relay_ctrl 的异步命令接口（post_xxx），由常驻协程串行执行；
    --        应答中回传的是当前缓存状态，最新真实状态会在执行完成后由 RELAY_STATUS_UPDATE 广播刷新。
    elseif cmd.type == "relay_open" then
        local ch = tonumber(cmd.channel)
        local posted = false
        if ch then posted = relay_ctrl.post_open(ch) end
        resp.ok = posted; resp.channel = ch; resp.relay = relay_ctrl.get_state()
    elseif cmd.type == "relay_close" then
        local ch = tonumber(cmd.channel)
        local posted = false
        if ch then posted = relay_ctrl.post_close(ch) end
        resp.ok = posted; resp.channel = ch; resp.relay = relay_ctrl.get_state()
    elseif cmd.type == "relay_toggle" then
        local ch = tonumber(cmd.channel)
        local posted = false
        if ch then posted = relay_ctrl.post_toggle(ch) end
        resp.ok = posted; resp.channel = ch; resp.relay = relay_ctrl.get_state()
    elseif cmd.type == "relay_all_open" then
        resp.ok = relay_ctrl.post_all_open(); resp.relay = relay_ctrl.get_state()
    elseif cmd.type == "relay_all_close" then
        resp.ok = relay_ctrl.post_all_close(); resp.relay = relay_ctrl.get_state()
    elseif cmd.type == "relay_read" then
        resp.ok = relay_ctrl.post_read(); resp.relay = relay_ctrl.get_state()

    -- 三色 LED 控制命令（三路互斥，同一时刻只亮一路；color 可选 red/green/blue/off）
    -- 【关键】LED 控制仅使用 gpio.set，不含 sys.wait，可在 C 层回调中直接执行，
    --        无需像继电器那样投递异步命令（不存在协程越界风险）。
    elseif cmd.type == "led_set" then
        local color = tostring(cmd.color or cmd.value or "")
        local set_ok = led.set_color(color)
        resp.ok = set_ok
        resp.color = color
        resp.led = led.get_state()
        if not set_ok then resp.error = "非法颜色(可选 red/green/blue/off)" end
    elseif cmd.type == "led_off" then
        led.off()
        resp.ok = true; resp.led = led.get_state()
    elseif cmd.type == "led_read" then
        resp.ok = true; resp.led = led.get_state()
    else
        resp = {error="未知命令", cmd=cmd.type or ""}
    end

    local resp_tlv = filter_valid_tlvs({
        { field_meaning = excloud.FIELD_MEANINGS.CONTROL_RESPONSE, data_type = excloud.DATA_TYPES.ASCII, value = json.encode(resp) },
    }, "命令应答")
    if #resp_tlv > 0 then
        excloud.send(resp_tlv, false)
    end
end

-- excloud 事件回调
local function on_excloud_event(event, data)
    log.info("用户回调函数", event, json.encode(data))

    if event == "connect_result" then
        if data.success then
            log.info("连接成功")
            mtn_log("aircloud", "连接成功")
        else
            log.info("连接失败: " .. (data.error or "未知错误"))
            mtn_log("aircloud", "连接失败:" .. tostring(data.error or "未知错误"))
        end
    elseif event == "auth_result" then
        if data.success then
            log.info("认证成功")
            mtn_log("aircloud", "认证成功")
        else
            log.info("认证失败: " .. (data.message or "?"))
            mtn_log("aircloud", "认证失败:" .. tostring(data.message or "?"))
        end
    elseif event == "message" then
        log.info("收到消息, seq:", data.header and data.header.sequence_num)
        for _, tlv in ipairs(data.tlvs or {}) do
            -- 诊断日志：逐条打印下行 TLV，便于确认平台实际下发的 Tag 与载荷
            log.info("aircloud", "下行TLV field:", tlv.field, "type:", tlv.type,
                "value:", string.sub(tostring(tlv.value), 1, 128))
            -- 兼容三种下行通道（任一命中即处理，便于平台上不同入口下发）：
            --   19   CONTROL_COMMAND  控制命令
            --   21   IRTU_DOWN        iRTU下行指令
            --   1281 RANDOM_DATA      自定义下行消息
            if tlv.field == excloud.FIELD_MEANINGS.CONTROL_COMMAND
                or tlv.field == excloud.FIELD_MEANINGS.IRTU_DOWN
                or tlv.field == excloud.FIELD_MEANINGS.RANDOM_DATA then
                handle_control_command(tlv.value)
            end
        end
    elseif event == "disconnect" then
        log.warn("与服务器断开连接")
        mtn_log("aircloud", "与服务器断开连接")
    elseif event == "reconnect_failed" then
        log.info("重连失败，已尝试 " .. data.count .. " 次")
        mtn_log("aircloud", "重连失败, 已尝试 " .. tostring(data.count) .. " 次")
    elseif event == "send_result" then
        if data.success then
            log.info("发送成功, 流水号: " .. (data.seq or "?"))
        else
            log.info("发送失败: " .. tostring(data.error_msg or "?"))
        end
    end
end

excloud.on(on_excloud_event)

-- AirCloud 主任务：初始化 + 定时上报
local function aircloud_task()
    -- 等待IP就绪
    while not socket.adapter(socket.dft()) do
        log.warn("aircloud_data", "wait IP_READY", socket.dft())
        sys.waitUntil("IP_READY", 1000)
    end
    sys.wait(1000)

    -- 配置 excloud（同时启用运维日志）
    local ok, err = excloud.setup({
        device_type = 1,
        use_getip = true, -- 使用getip服务
        transport = "tcp",
        auto_reconnect = true,
        reconnect_interval = 10,
        max_reconnect = 5,
        timeout = 30,
        mtn_log_enabled = true,                        -- 启用本地运维日志
        mtn_log_blocks = 4,                            -- 运维日志每个文件块数
        mtn_log_write_way = excloud.MTN_LOG_ADD_WRITE, -- 追加写入方式
        aircloud_mtn_log_enabled = true,               -- 启用 AirCloud 运维日志上传
    })
    if not ok then
        log.error("excloud.setup 初始化失败: " .. (err or "?"))
        return
    end
    log.info("excloud初始化成功")
    mtn_log("aircloud", "excloud.setup 初始化成功")

    ok, err = excloud.open()
    if not ok then
        log.error("开启excloud服务失败: " .. (err or "?"))
        return
    end
    log.info("excloud服务已开启")
    mtn_log("aircloud", "excloud 服务已开启")

    -- 上报计数（用于控制运维日志写入频率，避免日志文件被快速覆盖）
    local report_count = 0

    -- 定时上报
    while true do
        sys.wait(60000) --间隔1分钟上传一次，此间隔可根据实际情况自行选择

        -- 系统数据：发送时实时读取（系统API，不会重复采集传感器）
        local rssi = mobile.csq() or 0
        local iccid = mobile.iccid() or ""

        adc.open(adc.CH_CPU)
        local cpu_temp = adc.get(adc.CH_CPU) or 0
        adc.close(adc.CH_CPU)

        adc.open(adc.CH_VBAT)
        local vbat = adc.get(adc.CH_VBAT) or 3300
        adc.close(adc.CH_VBAT)

        -- 异步数据：空值兜底
        local _lat = lat or ""
        local _lng = lng or ""
        local _rtu_temp = rtu_temp or 0
        local _rtu_hum = rtu_hum or 0

        local tlv_list = {
            { field_meaning = excloud.FIELD_MEANINGS.SIGNAL_STRENGTH_4G,  data_type = excloud.DATA_TYPES.INTEGER, value = rssi },
            { field_meaning = excloud.FIELD_MEANINGS.SIM_ICCID,           data_type = excloud.DATA_TYPES.ASCII,   value = iccid },
            { field_meaning = excloud.FIELD_MEANINGS.TEMPERATURE,         data_type = excloud.DATA_TYPES.FLOAT,   value = _rtu_temp },
            { field_meaning = excloud.FIELD_MEANINGS.HUMIDITY,            data_type = excloud.DATA_TYPES.FLOAT,   value = _rtu_hum },
            { field_meaning = excloud.FIELD_MEANINGS.ENV_TEMPERATURE,     data_type = excloud.DATA_TYPES.INTEGER, value = cpu_temp },
            { field_meaning = excloud.FIELD_MEANINGS.VOLTAGE,             data_type = excloud.DATA_TYPES.INTEGER, value = vbat },
            { field_meaning = excloud.FIELD_MEANINGS.GNSS_LONGITUDE,      data_type = excloud.DATA_TYPES.ASCII,   value = _lng },
            { field_meaning = excloud.FIELD_MEANINGS.GNSS_LATITUDE,       data_type = excloud.DATA_TYPES.ASCII,   value = _lat },
            -- 4路继电器状态（自定义字段 268，ASCII 逗号分隔：'1'=吸合、'0'=断开）
            { field_meaning = RELAY_STATUS_FIELD,                         data_type = excloud.DATA_TYPES.ASCII,   value = relay_state_to_string(relay_state) },
        }

        -- 过滤无效字段（如未定位时的空经纬度、未就绪时的空ICCID），避免整包被丢弃
        local tlv_valid = filter_valid_tlvs(tlv_list, "周期上报")
        if #tlv_valid == 0 then
            log.warn("aircloud_data", "本轮无可上报字段, 跳过")
        else
            local send_ok, err_msg = excloud.send(tlv_valid, false)
            if not send_ok then
                log.info("发送数据失败: " .. tostring(err_msg or "?"))
            else
                log.info("数据发送成功")
                -- 网络业务正常，喂网络看门狗
                sys.publish("FEED_NETWORK_WATCHDOG")
                -- 运维日志：每 10 分钟记录一次周期上报正常，避免刷满日志文件
                report_count = report_count + 1
                if report_count % 10 == 1 then
                    mtn_log("aircloud", "周期上报正常, 累计:" .. report_count)
                end
            end
        end
    end
end

sys.taskInit(aircloud_task)
