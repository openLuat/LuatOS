--[[
@module  aircloud_data
@summary 8784 AirCloud 数据上报与云端下行控制
@version 1.0
@date    2026.09.27
@author  王世豪
@usage
本模块为 AirCloud 业务模块，核心业务逻辑为：
1、开机等 IP_READY 后 excloud.setup + excloud.open，自动重连；
2、按 config.aircloud.report_cycle（默认 180 秒）周期上报：
   - 4G信号强度(782)、ICCID(783)、IMEI(798)、电池电压(799,mV,INTEGER)、CPU温度(263,℃,FLOAT)、时间戳(1280)
3、处理云端下行命令（同时兼容 Tag 19 控制命令 / Tag 21 iRTU下行 / Tag 1281 自定义消息）：
   - "cycle:秒数"   修改上报频率（fskv 持久化，重启生效范围仅本次运行，受 min_cycle 限制）
   - "led:on|off|blink"   主灯 GPIO24 控制（blink 为亮 5 秒后灭）
   - "mode:cc|sip"  切换工作模式（写 fskv 后 3 秒重启，见 main.lua）
   - "phone:号码"   设置 CC 模式目标手机号（写 fskv，重启后生效）
   - "status"|"read_all"  回读设备当前状态
   - "update"|"fota"  手动触发一次 FOTA 升级检查（libfota3，先回执再异步执行）
   命令支持 JSON（{"type":"led_set","color":"on"}）与文本短命令两种形式，JSON 解析失败时按文本兜底；
4、每条命令执行后用 Tag 20（CONTROL_RESPONSE）回复 JSON 结果。


本文件没有对外接口，在 app_main.lua 中 require "aircloud_data" 即可加载运行；
]]

local config = require "config"
local cfg = config.aircloud
if not cfg.enabled then
    log.info("aircloud_data", "AirCloud 上报已关闭")
    return
end

local excloud = require "excloud"
-- FOTA 远程升级模块：云端下发 update 命令时手动触发一次检测
local update = require "update"
local TAG = "aircloud_data"

local FM = excloud.FIELD_MEANINGS
local DT = excloud.DATA_TYPES

-- 上报周期：fskv 持久化，web 端 cycle:N 可改；KEY 与 8780 出厂固件保持一致
local CYCLE_KEY = "report_cycle"

-- 当前 SIP 状态（由 sip_app_main 广播的 SIP_APP_STATE 事件更新）
local sip_state = "INIT"

-- 当前是否运行在 SIP 模式（由 main.lua 设置的 _G.WORK_MODE 决定）。
-- CC 模式下不加载 sip_app_main，没人广播 SIP_APP_STATE，SIP 状态无意义：
-- 此时周期上报丢弃该字段、status 回 "N/A"，避免上报恒为 "INIT" 的假数据。
local function is_sip_mode()
    return _G.WORK_MODE ~= "cc"
end
-- 主灯闪烁定时器句柄
local blink_timer

local function get_cycle()
    local v = fskv.get(CYCLE_KEY)
    if type(v) == "number" and v >= cfg.min_cycle then return v end
    return cfg.report_cycle
end

local function set_cycle(sec)
    local n = tonumber(sec)
    if not n then return false, "cycle 参数非数字" end
    if n < cfg.min_cycle then return false, "cycle 不能小于 " .. cfg.min_cycle .. " 秒" end
    fskv.set(CYCLE_KEY, n)
    return true, n
end

-- ==================== 上报字段有效性过滤 ====================
-- 背景：excloud.build_tlv 遇到一个无法编码的字段就判失败，excloud.send 会整包返回 false，
--       导致该轮全部正常字段一起被丢弃（典型：SIM 未就绪时 ICCID 为空串）。
-- 对策：组包后统一过滤，保证有效数据照常上报。该实现参照 8300 出厂固件。
local function filter_valid_tlvs(list, tag)
    local out = {}
    for _, item in ipairs(list) do
        local t, v = item.data_type, item.value
        local reason
        if t == nil or v == nil then
            reason = "值为空(nil)"
        elseif t == DT.ASCII or t == DT.UNICODE or t == DT.BINARY then
            if type(v) ~= "string" or #v == 0 then reason = "字符串为空" end
        elseif t == DT.INTEGER or t == DT.FLOAT then
            if type(v) ~= "number" then reason = "非数字(" .. type(v) .. ")" end
        end
        if reason then
            log.warn(TAG, tag, "跳过无效字段 field:", item.field_meaning, "原因:", reason)
        else
            out[#out + 1] = item
        end
    end
    return out
end

-- excloud.mtn_log(level, tag, ...)：第一个参数是日志级别，不是 tag，
-- 少了 "info" 会被 exmtn 判为非法级别（W/exmtn level 必须是...）导致运维日志一条都写不进去
local function mtn_log(...)
    pcall(excloud.mtn_log, "info", "aircloud", ...)
end

-- ==================== 命令应答 ====================
local function reply(resp)
    local tlv = filter_valid_tlvs({
        { field_meaning = FM.CONTROL_RESPONSE, data_type = DT.ASCII, value = json.encode(resp) },
    }, "命令应答")
    if #tlv > 0 then excloud.send(tlv, false) end
end

-- ==================== 文本短命令解析 ====================
-- 支持 "头:参数" / "头,参数" / "头#参数" 三种分隔符，以及无参数短命令
local function parse_text_command(value)
    local s = tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if #s == 0 then return nil end

    local head, arg = s:match("^([%a_]+)[:,#](.+)$")
    if head then
        head, arg = head:lower(), arg:gsub("^%s+", ""):gsub("%s+$", "")
        if head == "cycle" then return { type = "cycle", seconds = tonumber(arg) } end
        if head == "led" or head == "led_set" then return { type = "led_set", color = arg } end
        if head == "mode" then return { type = "mode_set", mode = arg } end
        if head == "phone" then return { type = "phone_set", number = arg } end
        return nil
    end

    local single = s:lower()
    if single == "status" or single == "read_all" then return { type = "status" } end
    if single == "led_off" then return { type = "led_set", color = "off" } end
    if single == "led_read" or single == "led" then return { type = "led_read" } end
    if single == "mode_read" or single == "mode" then return { type = "mode_read" } end
    if single == "phone_read" then return { type = "phone_read" } end
    if single == "update" or single == "fota" then return { type = "update" } end
    return nil
end

-- ==================== ADC 取值 ====================
-- adc.CH_CPU  ：返回 0.001℃ 为单位的整数，必须 /1000 得摄氏度。
-- adc.CH_VBAT ：返回 mV，直接上报。字段 799 业界约定即 mV
local function get_cpu_temp()
    adc.open(adc.CH_CPU)
    local raw = adc.get(adc.CH_CPU)
    adc.close(adc.CH_CPU)
    if raw and raw > 0 then return raw / 1000 end
    return nil
end

local function get_vbat_mv()
    adc.open(adc.CH_VBAT)
    local mv = adc.get(adc.CH_VBAT)
    adc.close(adc.CH_VBAT)
    return mv
end

-- ==================== LED 控制（仅 gpio.set，无 sys.wait，可在回调中直接执行） ====================
local function led_set(color)
    local pin = config.leds.main_pin
    if blink_timer then sys.timerStop(blink_timer) blink_timer = nil end
    color = tostring(color or ""):lower()
    if color == "on" then
        gpio.setup(pin, 1)
    elseif color == "off" then
        gpio.setup(pin, 0)
    elseif color == "blink" then
        gpio.setup(pin, 1)
        blink_timer = sys.timerStart(function()
            blink_timer = nil
            gpio.setup(pin, 0)
        end, 5000)
    else
        return false, "非法颜色(可选 on/off/blink)"
    end
    return true, color
end

-- ==================== 下行命令处理 ====================
local function handle_control_command(value)
    local ok, cmd = pcall(json.decode, tostring(value))
    if ok and type(cmd) == "table" then
        -- 兼容 8780 出厂固件下发的 {"command":"update"} 形式，本模块内部统一用 cmd.type 分发
        cmd.type = cmd.type or cmd.command
    end
    if not ok or type(cmd) ~= "table" or not cmd.type then
        cmd = parse_text_command(value)
    end
    if type(cmd) ~= "table" or not cmd.type then
        log.warn(TAG, "无效命令:", tostring(value))
        mtn_log("无效命令:" .. string.sub(tostring(value), 1, 64))
        return
    end
    log.info(TAG, "收到命令:", cmd.type)
    mtn_log("收到命令:" .. tostring(cmd.type))

    local resp = { }
    if cmd.type == "cycle" then
        local okc, msg = set_cycle(cmd.seconds)
        resp.ok = okc
        if okc then resp.cycle = msg else resp.error = msg end

    elseif cmd.type == "led_set" then
        local okc, msg = led_set(cmd.color or cmd.value)
        resp.ok = okc
        if okc then resp.color = msg else resp.error = msg end

    elseif cmd.type == "led_read" then
        resp.ok = true
        resp.led = gpio.get(config.leds.main_pin)

    elseif cmd.type == "mode_set" then
        -- 工作模式切换：SIP（云端通话，默认）/ CC（SIP↔手机中转）。
        -- 两套音频驱动对 Air1103 的 MIC 处理互斥（SIP 要开、CC 要关），无法运行时热切换，
        -- 因此做法是写 fskv 标记后重启，由 main.lua 按标记加载对应模块。
        local m = tostring(cmd.mode or cmd.value or ""):lower()
        if m ~= "sip" and m ~= "cc" then
            resp = { error = "模式仅支持 sip/cc", got = m }
        else
            fskv.set("work_mode", m)
            resp.ok = true
            resp.mode = m
            resp.rebooting = true
            reply(resp)               -- 先把结果回给云端，再重启
            mtn_log("切换工作模式:" .. m)
            sys.timerStart(pm.reboot, 3000)
            return
        end

    elseif cmd.type == "mode_read" then
        resp.ok = true
        resp.mode = fskv.get("work_mode") or "sip"

    elseif cmd.type == "phone_set" then
        -- CC 模式的目标手机号（SIP 呼入时拨打的号码），持久化到 fskv
        local num = tostring(cmd.number or cmd.value or ""):gsub("[^0-9+]", "")
        if #num == 0 then
            resp = { error = "手机号为空" }
        else
            fskv.set("cc_target_phone", num)
            resp.ok = true
            resp.phone = num
            resp.hint = "重启后生效（CC 模式启动时读取）"
        end

    elseif cmd.type == "phone_read" then
        resp.ok = true
        resp.phone = fskv.get("cc_target_phone") or ""

    elseif cmd.type == "status" then
        resp.cpu_temp_c = get_cpu_temp()        -- 摄氏度
        resp.vbat_mv = get_vbat_mv()            -- 毫伏
        resp.csq = mobile.csq() or 0
        resp.imei = mobile.imei() or ""
        resp.sip_username = config.sip.sip_username
        resp.sip_state = is_sip_mode() and sip_state or "N/A(CC模式无SIP状态)"
        resp.cycle = get_cycle()
        resp.work_mode = fskv.get("work_mode") or "sip"
        resp.cc_phone = fskv.get("cc_target_phone") or ""
        resp.timestamp = os.time()
        resp.ok = true

    elseif cmd.type == "update" then
        -- FOTA：手动触发一次升级检测(libfota3.check_update)。
        -- 检测流程内部会 sys.wait，且成功后 500ms 自动重启，因此先把回执发给云端再触发。
        -- update.check_update() 内部用 sys.taskInit，在本回调(C层直接调用)里执行是安全的。
        -- 注意：libfota3 有 running 互斥，若此刻开机检测仍在跑，本次请求会被跳过(仅日志提示)。
        resp.ok = true
        resp.hint = "已触发FOTA检测，结果见日志标签 fota/update"
        reply(resp)
        mtn_log("触发FOTA升级检查")
        update.check_update()
        return

    else
        resp = { error = "未知命令", cmd = cmd.type or "" }
    end

    reply(resp)
end

-- ==================== excloud 事件回调 ====================
local function on_excloud_event(event, data)
    data = data or {}
    if event == "connect_result" then
        log.info(TAG, "连接", data.success and "成功" or ("失败:" .. tostring(data.error)))
        mtn_log("连接" .. (data.success and "成功" or "失败"))
    elseif event == "auth_result" then
        log.info(TAG, "认证", data.success and "成功" or ("失败:" .. tostring(data.message)))
        mtn_log("认证" .. (data.success and "成功" or "失败"))
    elseif event == "message" then
        for _, tlv in ipairs(data.tlvs or {}) do
            log.info(TAG, "下行TLV field:", tlv.field, "value:", string.sub(tostring(tlv.value), 1, 128))
            if tlv.field == FM.CONTROL_COMMAND or tlv.field == FM.IRTU_DOWN or tlv.field == FM.RANDOM_DATA then
                handle_control_command(tlv.value)
            end
        end
    elseif event == "disconnect" then
        log.warn(TAG, "与服务器断开连接")
        mtn_log("与服务器断开连接")
    elseif event == "reconnect_failed" then
        log.warn(TAG, "重连失败，已尝试", data.count, "次")
        mtn_log("重连失败, 已尝试 " .. tostring(data.count) .. " 次")
    elseif event == "send_result" then
        if not data.success then
            log.warn(TAG, "发送失败:", tostring(data.error_msg or "?"))
        end
    end
end

excloud.on(on_excloud_event)

-- 记录 SIP 状态变化（供周期上报与 status 命令使用）
sys.subscribe("SIP_APP_STATE", function(state)
    sip_state = state or "?"
end)

-- ==================== 主任务 ====================
sys.taskInit(function()
    while not socket.adapter(config.adapter) do
        log.warn(TAG, "等待 IP_READY", config.adapter)
        sys.waitUntil("IP_READY", 1000)
    end
    sys.wait(1000)

    local ok, err = excloud.setup({
        device_type = 1,
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
        log.error(TAG, "excloud.setup 失败:", err or "?")
        return
    end
    log.info(TAG, "excloud 初始化成功")
    mtn_log("excloud.setup 初始化成功")

    ok, err = excloud.open()
    if not ok then
        log.error(TAG, "excloud.open 失败:", err or "?")
        return
    end
    log.info(TAG, "excloud 服务已开启")
    mtn_log("excloud 服务已开启")

    local report_count = 0
    while true do
        sys.wait(get_cycle() * 1000)

        local cpu_temp = get_cpu_temp()     -- 摄氏度（已 /1000）
        local vbat = get_vbat_mv()          -- 毫伏

        local tlv_list = {
            { field_meaning = FM.SIGNAL_STRENGTH_4G, data_type = DT.INTEGER, value = mobile.csq() },
            { field_meaning = FM.SIM_ICCID,          data_type = DT.ASCII,   value = mobile.iccid() },
            { field_meaning = FM.DEVICE_ID,          data_type = DT.ASCII,   value = mobile.imei() },
            -- 799 约定为 mV，INTEGER 原样上报
            { field_meaning = FM.VOLTAGE,            data_type = DT.INTEGER, value = vbat },
            -- 263 必须是 FLOAT：excloud 的 FLOAT 编码为 value*1000，平台解码时 /1000。
            -- 若用 INTEGER 直接传原始值，平台会当成 33000℃（旧版本就是这样，web 上显示 CPU 33000 C）
            { field_meaning = FM.ENV_TEMPERATURE,    data_type = DT.FLOAT,   value = cpu_temp },
            { field_meaning = FM.TIMESTAMP,          data_type = DT.INTEGER, value = os.time() },
            -- 8784 个性字段：SIP 通话状态（自定义 269）。
            -- CC 模式下无 sip_app_main，状态恒为 "INIT" 是假数据，置 nil 让 filter_valid_tlvs 丢弃该字段
            { field_meaning = cfg.sip_state_field,   data_type = DT.ASCII,
              value = is_sip_mode() and sip_state or nil },
        }

        local tlv_valid = filter_valid_tlvs(tlv_list, "周期上报")
        if #tlv_valid == 0 then
            log.warn(TAG, "本轮无可上报字段，跳过")
        else
            local send_ok, send_err = excloud.send(tlv_valid, false)
            if send_ok then
                report_count = report_count + 1
                log.info(TAG, "周期上报成功", "第", report_count, "次",
                         "CPU温度=", cpu_temp, "℃", "电压=", vbat, "mV", "SIP状态=", sip_state)
                -- 运维日志每 10 轮记一次，避免刷满日志文件
                if report_count % 10 == 1 then
                    mtn_log("周期上报正常, 累计:" .. report_count)
                end
            else
                log.warn(TAG, "周期上报失败:", tostring(send_err or "?"))
            end
        end
    end
end)
