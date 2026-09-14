--[[
@module remote
@summary 远程控制模块 - 处理云平台命令
@version 3.3
@date    2026.09.06
@usage
处理云平台下发的标准命令，应答以 TLV 自定义字段组帧（1296~1299）经 AirCloud 通道直发
（004.000.037 起 JSON 应答通道已移除）。
001.000.002 新增第 12 种命令 gnss_schedule：配置 GNSS 开启时间窗（书包场景上课时段省电），
参数经 kvstore 持久化，active_mode 订阅 GNSS_SCHEDULE_UPDATED 事件实时生效。
]]

local remote = {}
local config = require("config")
local kvstore = require("kvstore")
local create = require("create")
local excloud = require("excloud")

-- 自定义应答字段号（1280~1535 协议预留区，沿用 1290 起的固件自定义编号）
local FIELD_REPLY_MSG_ID   = 1296  -- ASCII：原样带回服务器下行命令的 msg_id（关联应答）
local FIELD_REPLY_COMMAND  = 1297  -- ASCII：命令名
local FIELD_REPLY_RESULT   = 1298  -- INTEGER：0=成功，非 0=失败
local FIELD_REPLY_MESSAGE  = 1299  -- ASCII：结果描述

-- 命令处理表
local command_handlers = {}

-- 发送命令应答（TLV 自定义字段组帧，经 AirCloud 通道直发）
-- reply_to 为服务器下行命令携带的 msg_id（可能为 nil，缺失时该字段省略）
local function send_reply(reply_to, command, result, message)
    local DT = excloud.DATA_TYPES
    local fields = {}
    if reply_to and tostring(reply_to) ~= "" then
        table.insert(fields, { field_meaning = FIELD_REPLY_MSG_ID, data_type = DT.ASCII, value = tostring(reply_to) })
    end
    if command and tostring(command) ~= "" then
        table.insert(fields, { field_meaning = FIELD_REPLY_COMMAND, data_type = DT.ASCII, value = tostring(command) })
    end
    table.insert(fields, { field_meaning = FIELD_REPLY_RESULT, data_type = DT.INTEGER, value = result or 0 })
    if message and tostring(message) ~= "" then
        table.insert(fields, { field_meaning = FIELD_REPLY_MESSAGE, data_type = DT.ASCII, value = tostring(message) })
    end
    create.send_aircloud(fields)
    log.info("remote", "发送命令应答(TLV):", command, result, message)
end

-- 解析 "HH:mm" 时间字符串为当日分钟数（0~1439），格式非法返回 nil
local function parse_hhmm(s)
    if type(s) ~= "string" then return nil end
    local h, m = s:match("^(%d%d):(%d%d)$")
    if not h then return nil end
    h, m = tonumber(h), tonumber(m)
    if h > 23 or m > 59 then return nil end
    return h * 60 + m
end

-- ========== MQTT 9 种标准命令处理 ==========

-- 1. get_device_data - 触发立即上报
function command_handlers.get_device_data(msg, cmd_msg)
    log.info("remote", "[MQTT] 收到 get_device_data")
    sys.publish("FORCE_REPORT")
    send_reply(cmd_msg.msg_id, "get_device_data", 0, "ok")
end

-- 2. change_mode - 切换工作模式
function command_handlers.change_mode(msg, cmd_msg)
    -- 兼容两种格式：
    -- 标准：{"command":"change_mode","data":{"params":{"mode":0}}}
    -- 扁平：{"cmd":"change_mode","mode":2}
    local params = cmd_msg.data and cmd_msg.data.params or {}
    local mode = tonumber(params.mode) or tonumber(cmd_msg.mode)
    local valid_modes = {[-1]=true, [0]=true, [1]=true, [2]=true}

    if not mode or not valid_modes[mode] then
        log.error("remote", "[MQTT] change_mode 参数无效:", params.mode)
        send_reply(cmd_msg.msg_id, "change_mode", 2, "参数错误: mode=" .. tostring(params.mode))
        return
    end

    local mode_names = {[-1]="未激活", [0]="常规模式", [1]="智能模式", [2]="GPS定位模式"}
    log.info("remote", "[MQTT] change_mode:", mode, mode_names[mode])

    kvstore.set_work_mode(mode)

    local lowpower_app = require("lowpower_app")
    if lowpower_app and lowpower_app.set_mode_by_device_mode then
        lowpower_app.set_mode_by_device_mode(mode)
    end

    send_reply(cmd_msg.msg_id, "change_mode", 0, "ok, mode=" .. mode)
    sys.timerStart(pm.reboot, 3000)
end

-- 3. call - SIP 呼叫（本硬件无音频/无 SIP，返回不支持）
function command_handlers.call(msg, cmd_msg)
    log.warn("remote", "[MQTT] 收到 call 命令，但本硬件不支持 SIP 通话")
    send_reply(cmd_msg.msg_id, "call", 4, "SIP 不支持（无音频硬件）")
end

-- 4. play_sound - 播放声音（本硬件无音频，返回不支持）
function command_handlers.play_sound(msg, cmd_msg)
    log.warn("remote", "[MQTT] 收到 play_sound 命令，但本硬件无音频功能")
    send_reply(cmd_msg.msg_id, "play_sound", 4, "音频不支持（无音频硬件）")
end

-- 5. open_light - 控制灯光（手动覆盖：1=强制亮（黄色，不充电时绿色），0=恢复自动状态机）
function command_handlers.open_light(msg, cmd_msg)
    local params = cmd_msg.data and cmd_msg.data.params or {}
    local status = tonumber(params.status)

    log.info("remote", "[MQTT] open_light:", status)

    local tools = require("tools")
    if status == 1 then
        if tools.led_set_manual then tools.led_set_manual(true) end
    elseif status == 0 then
        if tools.led_set_manual then tools.led_set_manual(false) end
    else
        send_reply(cmd_msg.msg_id, "open_light", 2, "参数错误: status=" .. tostring(status))
        return
    end
    send_reply(cmd_msg.msg_id, "open_light", 0, "ok")
end

-- 6. close_device - 关机
function command_handlers.close_device(msg, cmd_msg)
    log.info("remote", "[MQTT] 收到 close_device 关机命令")
    send_reply(cmd_msg.msg_id, "close_device", 0, "ok, shutting down")
    sys.wait(3000)
    pm.shutdown()
end

-- 7. set_report_interval - 设置上报间隔（当前固件不支持）
-- 上报节奏已固定为 GNSS 三态策略（实时上报1s / GNSS开10s / GNSS关300s，常量在 active_mode 内），
-- 无自定义间隔入口，命令保留仅为协议兼容，回执明确告知不支持
function command_handlers.set_report_interval(msg, cmd_msg)
    local params = cmd_msg.data and cmd_msg.data.params or {}
    local interval = tonumber(params.interval_seconds)

    if not interval or interval < 10 or interval > 86400 then
        log.error("remote", "[MQTT] set_report_interval 参数无效:", params.interval_seconds)
        send_reply(cmd_msg.msg_id, "set_report_interval", 2, "参数错误: interval_seconds=" .. tostring(params.interval_seconds))
        return
    end

    log.info("remote", "[MQTT] 收到 set_report_interval:", interval, "秒，但当前固件不支持自定义上报间隔")
    send_reply(cmd_msg.msg_id, "set_report_interval", 4, "当前固件为GNSS三态固定上报节奏(实时1s/GNSS开10s/GNSS关300s)，不支持自定义间隔")
end

-- 8. set_volume - 设置音量（本硬件无音频，仅保存音量值，返回不支持）
function command_handlers.set_volume(msg, cmd_msg)
    local params = cmd_msg.data and cmd_msg.data.params or {}
    local volume = tonumber(params.volume)

    if not volume or volume < 1 or volume > 100 then
        log.error("remote", "[MQTT] set_volume 参数无效:", params.volume)
        send_reply(cmd_msg.msg_id, "set_volume", 2, "参数错误: volume=" .. tostring(params.volume))
        return
    end

    log.info("remote", "[MQTT] set_volume:", volume)
    kvstore.set_audio_volume(volume)

    send_reply(cmd_msg.msg_id, "set_volume", 4, "音频不支持（无音频硬件）")
end

-- 9. update - 触发OTA升级
function command_handlers.update(msg, cmd_msg)
    log.info("remote", "[MQTT] 收到 update 命令, 触发OTA升级")
    send_reply(cmd_msg.msg_id, "update", 0, "ok, starting update")
    local update = require("update")
    update.check_update()
end

-- 10. fota_mode - 切换FOTA模式
-- JSON: {"command":"fota_mode","data":{"params":{"mode":3}}}
-- mode: 3=libfota3(只能合宙人员根据客户IMEI升级), 2=libfota2(IoT平台,客户自行管理)
function command_handlers.fota_mode(msg, cmd_msg)
    local mode = cmd_msg.data and cmd_msg.data.params and cmd_msg.data.params.mode
    if not mode then
        log.warn("remote", "fota_mode 缺少 mode 参数")
        send_reply(cmd_msg.msg_id, "fota_mode", 1, "缺少 mode 参数")
        return
    end
    log.info("remote", "[MQTT] 收到 fota_mode 命令, mode:", mode)
    local update = require("update")
    update.set_fota_mode(mode)
    send_reply(cmd_msg.msg_id, "fota_mode", 0, "ok, fota mode set to " .. mode)
end

-- 11. fast_report - 进入实时上报模式
-- 兼容两种格式（无其他参数）：
-- 标准：{"command":"fast_report"}
-- 扁平：{"cmd":"fast_report"}
-- 行为（由 active_mode 状态机执行）：
--   无论当前 GNSS 开启/关闭，立即进入实时上报模式：每秒上报一次报文，
--   除 1293/1294 外其余 TLV 都上报，持续 1 分钟；
--   进行中重复收到本命令则重置 1 分钟倒计时（续期）；
--   结束时强制先进入 GNSS 开启模式，再按 gsensor 条件正常评估。
function command_handlers.fast_report(msg, cmd_msg)
    log.info("remote", "[MQTT] 收到 fast_report，进入实时上报模式")
    sys.publish("FAST_REPORT_START")
    send_reply(cmd_msg.msg_id, "fast_report", 0, "ok, fast report started (1min)")
end

-- 12. gnss_schedule - 配置 GNSS 开启时间窗（001.000.002 新增）
-- JSON: {"command":"gnss_schedule","msg_id":"...","data":{"params":{"enable":1,"start":"08:30","end":"18:00"}}}
-- enable: 1=启用时间窗（窗内 GNSS 强制开，窗外强制关）；0=清除配置，恢复纯 gsensor 逻辑
-- start/end: "HH:mm" 24 小时制；start > end 视为跨零点（如 22:00-06:00）；start == end 视为参数错误
-- 行为：参数校验通过后 kvstore 持久化（重启自动恢复），发布 GNSS_SCHEDULE_UPDATED
-- 通知 active_mode 刷新缓存并立即重新评估；实时上报(fast_report)不受时间窗限制。
-- 注意：时间窗判定依赖 NTP 对时，设备时间未同步时时间窗不生效（按原 gsensor 逻辑运行）。
function command_handlers.gnss_schedule(msg, cmd_msg)
    local params = cmd_msg.data and cmd_msg.data.params or {}
    local enable = tonumber(params.enable)

    log.info("remote", "[MQTT] 收到 gnss_schedule, enable:", enable)

    -- 清除配置：enable=0，恢复纯 gsensor 逻辑
    if enable == 0 then
        kvstore.set_gnss_schedule(nil)
        sys.publish("GNSS_SCHEDULE_UPDATED")
        send_reply(cmd_msg.msg_id, "gnss_schedule", 0, "ok, schedule cleared")
        return
    end

    -- 启用时间窗：校验 start/end
    if enable ~= 1 then
        send_reply(cmd_msg.msg_id, "gnss_schedule", 2, "参数错误: enable=" .. tostring(params.enable))
        return
    end

    local start_min = parse_hhmm(params.start)
    local end_min = parse_hhmm(params["end"])
    if not start_min or not end_min then
        send_reply(cmd_msg.msg_id, "gnss_schedule", 2,
            "参数错误: start/end 需为 HH:mm(如 08:30), start=" .. tostring(params.start) .. ", end=" .. tostring(params["end"]))
        return
    end
    if start_min == end_min then
        send_reply(cmd_msg.msg_id, "gnss_schedule", 2, "参数错误: start 与 end 相同")
        return
    end

    local ok = kvstore.set_gnss_schedule({ enable = 1, start = params.start, ["end"] = params["end"] })
    if not ok then
        send_reply(cmd_msg.msg_id, "gnss_schedule", 3, "保存失败")
        return
    end

    sys.publish("GNSS_SCHEDULE_UPDATED")
    local cross = start_min > end_min and "（跨零点）" or ""
    send_reply(cmd_msg.msg_id, "gnss_schedule", 0,
        "ok, " .. params.start .. "-" .. params["end"] .. cross .. " 窗内GNSS常开/窗外强制关")
    excloud.mtn_log("info", "gnss_schedule",
        "配置GNSS时间窗", "时段", params.start .. "-" .. params["end"], "跨零点", start_min > end_min and "是" or "否")
end

-- ========== 命令分发 ==========

-- 解析并执行命令
-- 注意：REMOTE_COMMAND 来自消息回调(非协程)，handler 内部可能调用 sys.wait，
-- 因此整个执行过程放入独立协程，避免"attempt to yield from outside a coroutine"
local function execute_command(raw_command)
    log.info("remote", "收到命令:", type(raw_command), raw_command)

    sys.taskInit(function()
        -- 统一 JSON 格式: {"command":"change_mode","data":{"params":{"mode":0}}} 或 {"cmd":"change_mode","mode":2}
        local ok, parsed = pcall(json.decode, raw_command)
        if not ok or type(parsed) ~= "table" then
            log.info("remote", "非JSON命令消息，已忽略:", raw_command)
            return
        end

        local cmd_name = parsed.command or parsed.cmd
        log.info("remote", "执行命令:", cmd_name)
        local handler = command_handlers[cmd_name]
        if handler then
            handler(parsed, parsed)
        else
            log.warn("remote", "未知命令:", cmd_name)
            send_reply(parsed.msg_id, cmd_name, 1, "未知命令: " .. tostring(cmd_name))
        end
    end)
end

-- MQTT 命令入口（sys.subscribe 回调 → 直接执行）
function remote.handle_command(command)
    log.info("remote", "收到订阅事件:", command.command)
    execute_command(command.command)
end

-- 初始化
local _remote_inited = false
function remote.init()
    if _remote_inited then return end
    _remote_inited = true
    log.info("remote", "远程控制模块初始化")
    sys.subscribe("REMOTE_COMMAND", remote.handle_command)
    log.info("remote", "远程控制模块初始化完成")
end

return remote
