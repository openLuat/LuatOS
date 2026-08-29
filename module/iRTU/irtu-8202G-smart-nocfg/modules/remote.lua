--[[
@module remote
@summary 远程控制模块 - 处理云平台命令
@version 3.1
@date    2026.07.17
@usage
处理云平台下发的标准命令，通过 create.send() 发送回复。
]]

local remote = {}
local config = require("config")
local kvstore = require("kvstore")
local create = require("create")

-- 命令处理表
local command_handlers = {}

-- 构建通用消息框架
local function build_msg(msg_type, reply_to)
    local imei = mobile.imei() or "000000000000000"
    local ts = os.time()
    return {
        msg_id = imei .. "-" .. ts,
        reply_to = reply_to,
        imei = imei,
        ts = ts,
        type = msg_type,
        data = {}
    }
end

-- 发送命令应答（通过 create.lua 通道）
local function send_reply(reply_to, command, result, message)
    local msg = build_msg("command_reply", reply_to)
    msg.data = {
        command = command,
        result = result,
        message = message
    }
    local payload = json.encode(msg)
    create.send(payload)
    log.info("remote", "发送命令应答:", payload)
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

-- 5. open_light - 控制灯光（手动覆盖：1=强制亮（红色，充电充满时绿色），0=恢复自动状态机）
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

-- 7. set_report_interval - 设置上报间隔
function command_handlers.set_report_interval(msg, cmd_msg)
    local params = cmd_msg.data and cmd_msg.data.params or {}
    local interval = tonumber(params.interval_seconds)

    if not interval or interval < 10 or interval > 86400 then
        log.error("remote", "[MQTT] set_report_interval 参数无效:", params.interval_seconds)
        send_reply(cmd_msg.msg_id, "set_report_interval", 2, "参数错误: interval_seconds=" .. tostring(params.interval_seconds))
        return
    end

    log.info("remote", "[MQTT] set_report_interval:", interval, "秒")
    kvstore.set_report_interval(interval)
    send_reply(cmd_msg.msg_id, "set_report_interval", 0, "ok, interval=" .. interval)
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
