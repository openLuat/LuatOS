--[[
@module remote
@summary 远程控制模块 - 处理云平台命令
@version 3.2
@date    2026.09.05
@usage
处理云平台下发的标准命令，应答以 TLV 自定义字段组帧（1296~1299）经 AirCloud 通道直发
（004.000.037 起 JSON 应答通道已移除）。

=== 8203 相对 8202G 的差异（T04） ===
 1. play_sound / set_volume：**不再一律回"不支持"**。
    依据：8203 的 V 系列（Air780EHV）**有音频硬件**（【图】AW8733 功放，PA_EN=GPIO26；
    【官网】仅国内版支持 Mic/Speaker）。判据用 config.AUDIO_CONFIG.SUPPORTED（板级派生，
    仅 V 系列为 true）；H/U/N 系列维持"不支持"回执。
 2. 新增 3 条 8203 工业专属命令：set_do / get_dio / rs485_send。
    rs485_send 在 RS485 未初始化（uart/baud 仍为【待核】nil）时明确回失败，不做静默丢弃。
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

-- 4. play_sound - 播放声音
-- ★ 8203 改动：V 系列（Air780EHV）有音频硬件（【图】AW8733 + PA_EN=GPIO26），
--   依据 config.AUDIO_CONFIG.SUPPORTED 判定；H/U/N 系列维持"不支持"回执。
-- JSON: {"command":"play_sound","data":{"params":{"file":"/luadb/xxx.amr"}}}
function command_handlers.play_sound(msg, cmd_msg)
    local params = cmd_msg.data and cmd_msg.data.params or {}
    local file = params.file or params.sound

    if not file or tostring(file) == "" then
        send_reply(cmd_msg.msg_id, "play_sound", 2, "参数错误: 缺少 file=" .. tostring(file))
        return
    end

    if not (config.AUDIO_CONFIG and config.AUDIO_CONFIG.SUPPORTED) then
        log.warn("remote", "[MQTT] 收到 play_sound，但本板无音频硬件（非 V 系列）")
        send_reply(cmd_msg.msg_id, "play_sound", 4, "音频不支持（仅 Air780EHV/V 系列有音频硬件）")
        return
    end

    local ok, audio = pcall(require, "audio_app")
    if not ok or type(audio) ~= "table" or not audio.play_file then
        send_reply(cmd_msg.msg_id, "play_sound", 4, "音频模块不可用")
        return
    end

    local ok_play, err_play = audio.play_file(tostring(file))
    send_reply(cmd_msg.msg_id, "play_sound", ok_play and 0 or 3,
        ok_play and ("ok, playing " .. tostring(file)) or ("播放失败: " .. tostring(err_play)))
end

-- 5. open_light - 控制灯光（手动覆盖：1=网络/状态灯强制常亮，0=交还自动状态机）
-- 注：充电灯不受本命令影响，始终按充电状态自动显示。
function command_handlers.open_light(msg, cmd_msg)
    local params = cmd_msg.data and cmd_msg.data.params or {}
    local status = tonumber(params.status)

    log.info("remote", "[MQTT] open_light:", status)

    local tools = require("tools")
    if status == 1 then
        tools.led_set_manual(true)
    elseif status == 0 then
        tools.led_set_manual(false)
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

-- 8. set_volume - 设置音量
-- ★ 8203 改动：V 系列有音频硬件，保存后**真正下发**到 audio 模块；
--   H/U/N 系列维持"已保存但不支持"回执（与 8202G 行为一致）。
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

    if not (config.AUDIO_CONFIG and config.AUDIO_CONFIG.SUPPORTED) then
        send_reply(cmd_msg.msg_id, "set_volume", 4, "音量已保存，但音频不支持（仅 V 系列有音频硬件）")
        return
    end

    local ok, audio = pcall(require, "audio_app")
    if not ok or type(audio) ~= "table" or not audio.set_volume then
        send_reply(cmd_msg.msg_id, "set_volume", 4, "音量已保存，但音频模块不可用")
        return
    end

    local ok_set = audio.set_volume(volume)
    send_reply(cmd_msg.msg_id, "set_volume", ok_set and 0 or 4,
        ok_set and ("ok, volume=" .. volume) or "音量已保存，但下发失败")
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
--   除 1301/1302 外其余 TLV 都上报，持续 1 分钟；
--   进行中重复收到本命令则重置 1 分钟倒计时（续期）；
--   结束时强制先进入 GNSS 开启模式，再按 gsensor 条件正常评估。
function command_handlers.fast_report(msg, cmd_msg)
    log.info("remote", "[MQTT] 收到 fast_report，进入实时上报模式")
    sys.publish("FAST_REPORT_START")
    send_reply(cmd_msg.msg_id, "fast_report", 0, "ok, fast report started (1min)")
end

-- ========== 8203 工业专属命令 ==========

-- 12. set_do - 设置对外 DO 输出（端子语义，dio 内部处理硬件反相）
-- JSON: {"command":"set_do","data":{"params":{"ch":1,"level":1}}}
-- level: 1=端子高 / 0=端子低
function command_handlers.set_do(msg, cmd_msg)
    local params = cmd_msg.data and cmd_msg.data.params or {}
    local ch = tonumber(params.ch)
    local level = tonumber(params.level)

    if not ch or ch < 1 or ch ~= math.floor(ch) then
        send_reply(cmd_msg.msg_id, "set_do", 2, "参数错误: ch=" .. tostring(params.ch))
        return
    end
    if level ~= 0 and level ~= 1 then
        send_reply(cmd_msg.msg_id, "set_do", 2, "参数错误: level=" .. tostring(params.level))
        return
    end

    local ok, dio = pcall(require, "dio")
    if not ok or type(dio) ~= "table" or not dio.do_set then
        send_reply(cmd_msg.msg_id, "set_do", 3, "dio 模块不可用")
        return
    end

    local ok_set, err_set = dio.do_set(ch, level)
    if not ok_set then
        send_reply(cmd_msg.msg_id, "set_do", 3, tostring(err_set or "无此通道"))
        return
    end
    send_reply(cmd_msg.msg_id, "set_do", 0, string.format("ok, DO%d 端子电平=%d", ch, level))
end

-- 13. get_dio - 查询各 DO/DI 通道当前端子电平
-- JSON: {"command":"get_dio"}
-- 回执 message 形如：DO1(GPIO28)=0,DO2(GPIO38)=0,DI1(GPIO22)=1
function command_handlers.get_dio(msg, cmd_msg)
    local ok, dio = pcall(require, "dio")
    if not ok or type(dio) ~= "table" or not dio.get_status then
        send_reply(cmd_msg.msg_id, "get_dio", 3, "dio 模块不可用")
        return
    end

    local st = dio.get_status() or {}
    if not st.inited then
        send_reply(cmd_msg.msg_id, "get_dio", 3, "dio 未初始化（config.DIO_CONFIG.ENABLE=false 或本系列无对外 IO）")
        return
    end

    local parts = {}
    for i, pin in ipairs(st.do_pins or {}) do
        if pin then
            local lv = dio.do_get and dio.do_get(i)
            parts[#parts + 1] = string.format("DO%d(GPIO%s)=%s", i, tostring(pin), tostring(lv))
        end
    end
    for i, pin in ipairs(st.di_pins or {}) do
        if pin then
            -- DI 为主控侧原始电平（隔离级极性【待核】，不折算成端子电平）
            local lv = dio.di_get and dio.di_get(i)
            parts[#parts + 1] = string.format("DI%d(GPIO%s)=%s", i, tostring(pin), tostring(lv))
        end
    end

    if #parts == 0 then
        send_reply(cmd_msg.msg_id, "get_dio", 3, "无可用 IO 通道")
        return
    end
    send_reply(cmd_msg.msg_id, "get_dio", 0, table.concat(parts, ","))
end

-- 14. rs485_send - 向 RS485/UART 对外口发送十六进制数据
-- JSON: {"command":"rs485_send","data":{"params":{"hex":"AABB"}}}
-- ⚠️ RS485 的 uart/baud 仍为【待核】nil 时，模块不会建口，本命令明确回失败（不静默丢弃）
function command_handlers.rs485_send(msg, cmd_msg)
    local params = cmd_msg.data and cmd_msg.data.params or {}
    local hex = params.hex

    if type(hex) ~= "string" or #hex == 0 or (#hex % 2) ~= 0 or hex:match("[^0-9A-Fa-f]") then
        send_reply(cmd_msg.msg_id, "rs485_send", 2, "参数错误: hex=" .. tostring(hex))
        return
    end

    local ok, rs485 = pcall(require, "rs485")
    if not ok or type(rs485) ~= "table" or not rs485.send then
        send_reply(cmd_msg.msg_id, "rs485_send", 3, "rs485 模块不可用")
        return
    end

    local st = (rs485.get_status and rs485.get_status()) or {}
    if not st.inited then
        send_reply(cmd_msg.msg_id, "rs485_send", 3,
            "485 功能暂未启用（config.RS485_CONFIG.ENABLE=false，待明确现场 485 设备后再开发）")
        return
    end

    local data = string.fromHex(hex)
    local ok_send = rs485.send(data)
    send_reply(cmd_msg.msg_id, "rs485_send", ok_send and 0 or 3,
        ok_send and (string.format("ok, sent %d bytes", #data)) or "发送失败")
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
