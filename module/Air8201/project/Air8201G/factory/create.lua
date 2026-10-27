--[[
@module  create
@summary AirCloud 云平台连接模块
@usage   单通道：excloud 直连 AirCloud，TLV 结构化上报
         外部模块通过 create.send_aircloud(tlv) 发送 TLV（唯一上行通道）
]]
create = {}

local excloud = require("excloud")

local datalink, defChan = {}, 1

sys.subscribe("IP_READY", function()
    log.info("create", "网络注册已成功")
end)

sys.subscribe("IP_LOSE", function(adapter)
    log.info("create", "网络注册失败", (adapter or -1) == socket.LWIP_GP)
end)

-- 获取连接状态
function create.is_connected()
    return datalink[defChan] or false
end

-- 发送 TLV 数据到 AirCloud（独立消息，由 aircloudTask 订阅处理）
-- @param data table TLV 字段数组，结构为 {field_meaning, data_type, value}
function create.send_aircloud(data)
    sys.publish("AIRCLOUD_SEND_1", data)
end

---------------------------------------------------------- AirCloud ----------------------------------------------------------
local function aircloudTask(cid, prot, keepAlive, timeout, uid, ssl, qos)
    cid = cid or 1
    qos = qos or 0

    -- TLV 直发通道：订阅在连接前注册，避免先 publish 导致消息丢失
    sys.subscribe("AIRCLOUD_SEND_" .. cid, function(tlv_data)
        if type(tlv_data) == "table" and #tlv_data > 0 then
            log.info("create", "收到 AIRCLOUD_SEND_", cid, "TLV字段数:", #tlv_data)
            local ok, err = excloud.send(tlv_data, false)
            log.info("create", "TLV发送结果", ok, err)
        end
    end)

    -- 等待网络
    while not socket.adapter(socket.dft()) do
        sys.waitUntil("IP_READY", 1000)
    end

    -- 处理官方 CONTROL_COMMAND（tag 19，ASCII）：led:blink|on|off
    -- 处理后仍照常发布 REMOTE_COMMAND，两套协议互不影响；结果通过 CONTROL_RESPONSE(tag 20) 回复
    local function handle_control_command(value)
        local cmd = tostring(value or "")
        local resp = "命令执行成功"

        local led_cmd = cmd:match("^led:(%w+)$")
        if led_cmd then
            local tools = require("tools")
            if led_cmd == "blink" then
                tools.led_force("blink", 5)
            elseif led_cmd == "on" then
                tools.led_force("on")
            elseif led_cmd == "off" then
                tools.led_force("off")
            else
                resp = "未知的LED命令: " .. led_cmd
            end
        else
            resp = "未知命令格式: " .. cmd
        end

        log.info("create", "CONTROL_COMMAND:", cmd, "→", resp)
        local ok_send, err_send = excloud.send({
            { field_meaning = excloud.FIELD_MEANINGS.CONTROL_RESPONSE,
              data_type = excloud.DATA_TYPES.ASCII, value = resp }
        }, false)
        if not ok_send then
            log.warn("create", "发送 CONTROL_RESPONSE 失败:", tostring(err_send))
        end
    end

    excloud.on(function(event, data)
        log.info("create", "excloud事件", event)
        if event == "connect_result" then
            if data.success then
                datalink[cid] = true
                sys.publish("CLOUD_CONNECTED")
                log.info("create", "AirCloud连接成功")
            else
                log.info("create", "AirCloud连接失败", data.error)
            end
        elseif event == "auth_result" then
            log.info("create", "认证结果", data.success and "成功" or ("失败: " .. tostring(data.message)))
        elseif event == "message" then
            for _, tlv in ipairs(data.tlvs) do
                if tlv.field == excloud.FIELD_MEANINGS.CONTROL_COMMAND then
                    handle_control_command(tlv.value)
                end
                -- 统一通过 REMOTE_COMMAND 分发到 remote.lua
                sys.publish("REMOTE_COMMAND", {command = tlv.value, raw = tlv})
            end
        elseif event == "disconnect" then
            datalink[cid] = false
            log.warn("create", "AirCloud断开连接")
        elseif event == "send_result" then
            log.info("create", "发送结果", data.success and "成功" or "失败")
        end
    end)

    sys.wait(1000)
    local setup_params = {
        device_type = 1,
        use_getip = true,
        transport = (prot == "mqtt") and "mqtt" or "tcp",
        auto_reconnect = true,
        reconnect_interval = 10,
        max_reconnect = 5,
        timeout = 30,
        qos = qos,
        mtn_log_enabled = true,
        aircloud_mtn_log_enabled = true,
        mtn_log_blocks = 2,
        mtn_log_write_way = excloud.MTN_LOG_CACHE_WRITE
    }

    local ok, err_msg = excloud.setup(setup_params)
    if not ok then
        log.info("create", "excloud初始化失败", err_msg)
        return
    end
    ok, err_msg = excloud.open()
    if not ok then
        log.info("create", "excloud开启失败", err_msg)
        return
    end
    log.info("create", "AirCloud服务已开启")

    -- 30s 主帧持续上行即链路保活，本任务无需额外心跳，常驻即可
    while true do
        sys.wait(60000)
    end
end

---------------------------------------------------------- 连接分发 ----------------------------------------------------------
local function connect(conf)
    while not socket.adapter(socket.dft()) do
        sys.waitUntil("IP_READY", 1000)
    end

    for k, v in pairs(conf or {}) do
        if v[1] and v[1]:upper() == "AIRCLOUD" then
            local taskName = "DTU_" .. tostring(k)
            log.warn("create", "启动 AirCloud 连接")
            sys.taskInitEx(aircloudTask, taskName, function() end, k, unpack(v, 2))
        end
    end
end

-- 启动云平台连接
-- @param cfg_sheet 从 db 加载的配置表（含 gnss.network 字段）
function create.start(cfg_sheet)
    local network = cfg_sheet and cfg_sheet.gnss and cfg_sheet.gnss.network
    if not network or not network.conf or #network.conf == 0 then
        log.warn("create", "无 network 配置，跳过云平台连接")
        return
    end

    -- 筛选激活的通道
    local conf_on = network.conf_on or {}
    local active_conf = {}
    for i, v in ipairs(network.conf) do
        local enable = conf_on[i]
        if enable == nil then enable = 1 end
        if enable == 1 and v and #v > 0 then
            table.insert(active_conf, v)
        end
    end

    if #active_conf == 0 then
        log.warn("create", "没有激活的网络通道")
        return
    end

    log.info("create", "启动", #active_conf, "个网络通道")
    sys.taskInit(connect, active_conf)
end

return create
