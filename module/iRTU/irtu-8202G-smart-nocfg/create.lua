--[[
@module  create
@summary 云平台连接模块（AirCloud + MQTT + TCP/UDP）
@version 6.0
@date    2026.07.17
@usage
协议支持：
1. AIRCLOUD - 合宙 AirCloud 云平台
2. MQTT    - 标准 MQTT 协议
3. SOCKET  - TCP/UDP 直连

配置从 db 持久化存储的 gnss.network 中读取。
外部模块通过 create.send(payload) 发送数据。
]]
create = {}

local libnet = require "libnet"
local dtulib = require "dtulib"
local excloud = require("excloud")

local datalink, defChan = {}, 1

-- 订阅网络事件
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

-- 发送数据到云平台（默认通道1，json 字符串，供 TCP/MQTT 通道使用）
function create.send(payload)
    sys.publish("NET_SENT_RDY_1", "CID_1", payload)
end

-- 发送 TLV 数据到 AirCloud 通道（独立消息，供 aircloudTask 处理）
-- @param data table TLV 字段数组，结构为 {field_meaning, data_type, value}
function create.send_aircloud(data)
    sys.publish("AIRCLOUD_SEND_1", data)
end

---------------------------------------------------------- TCP/UDP ----------------------------------------------------------
local function tcpTask(dName, cid, prot, ping, timeout, addr, port, uid, ssl)
    cid, prot, timeout, uid = cid or 1, prot:upper(), timeout or 120, uid or 1
    local outputSocket = {}
    local idx = 0
    local netc = socket.create(nil, dName)
    local isUdp = prot == "UDP"
    local isSsl = ssl == "ssl"
    local rx_buff = zbuff.create(256)

    -- 订阅发送数据请求
    local subMessage = function(data, data2)
        if data and data ~= "mqttrecv" and data ~= "disconnect" then
            if data == "CID_" .. cid or not data:match("CID_") then
                table.insert(outputSocket, data2 or data)
                sys_send(dName, socket.EVENT, 0)
            end
        end
    end
    sys.subscribe("NET_SENT_RDY_" .. uid, subMessage)

    socket.config(netc, nil, isUdp, isSsl)
    while true do
        -- 等待网络
        while not socket.adapter(socket.dft()) do
            sys.waitUntil("IP_READY", 1000)
        end

        local result = libnet.connect(dName, timeout * 1000, netc, addr, port)
        if result then
            idx = 0
            log.info("create", "TCP连接成功", dName, addr, port)
            datalink[cid] = true
            sys.publish("CLOUD_CONNECTED")

            while true do
                local result, param = libnet.wait(dName, timeout * 1000, netc)
                if not result then
                    log.info("create", "网络异常", dName, addr, port)
                    break
                end

                -- 心跳包
                if param == false then
                    local ping_data = (ping and ping ~= "") and dtulib.fromHexnew(ping) or nil
                    if ping_data then
                        libnet.tx(dName, nil, netc, ping_data)
                    end
                else
                    -- 接收服务器数据
                    local succ, _, _, _ = socket.rx(netc, rx_buff)
                    if not succ then
                        log.info("create", "服务器断开", dName, addr, port)
                        break
                    end
                    if rx_buff:used() > 0 then
                        local data = rx_buff:toStr(0, rx_buff:used())
                        log.info("create", "TCP收到服务器数据", data)
                        -- 统一通过 REMOTE_COMMAND 分发到 remote.lua
                        sys.publish("REMOTE_COMMAND", {command = data, raw = data})
                    end
                    rx_buff:del()
                end

                -- 发送待发送数据
                if #outputSocket > 0 then
                    local data = table.concat(outputSocket)
                    outputSocket = {}
                    libnet.tx(dName, nil, netc, data)
                end
            end
        else
            log.info("create", "TCP连接失败", dName, addr, port)
        end

        datalink[cid] = false
        libnet.close(dName, 5000, netc)
        sys.wait((2 * idx) * 1000)
        if idx > 9 then
            mobile.flymode(0, true)
            mobile.flymode(1, true)
            sys.wait(1000)
            mobile.flymode(0, false)
            mobile.flymode(1, false)
            idx = 1
        else
            idx = idx + 1
        end
    end
end

---------------------------------------------------------- MQTT ----------------------------------------------------------
local function mqttTask(cid, keepAlive, timeout, addr, port, usr, pwd, cleansession, sub, pub, qos, retain, uid, clientID, addImei, ssl, will, ...)
    cid, keepAlive, timeout, uid = cid or 1, keepAlive or 300, timeout, uid
    qos, retain = qos or 0, retain or 0
    cleansession = cleansession == 1
    addImei = addImei == 1
    clientID = (clientID == "" or not clientID) and mobile.imei() or clientID
    -- 处理主题列表：替换变量占位符
    local function parseTopicList(str)
        local topics = dtulib.split(str, ";")
        for i = 1, #topics, 2 do
            local tmp = dtulib.split(topics[i], "/")
            for v = 1, #tmp do
                if tmp[v]:lower() == "imei" then tmp[v] = mobile.imei() end
                if tmp[v]:lower() == "muid" then tmp[v] = mobile.muid() end
                if tmp[v]:lower() == "iccid" then tmp[v] = mobile.iccid() end
                if tmp[v]:lower() == "productkey" or tmp[v]:lower() == "${productkey}" then
                    tmp[v] = _G.PRODUCT_KEY or ""
                end
                if tmp[v]:lower() == "devicename" or tmp[v]:lower() == "${devicename}" then
                    tmp[v] = mobile.imei()
                end
            end
            topics[i] = table.concat(tmp, "/")
            -- addImei=1 时在主题末尾追加 IMEI
            if addImei then
                topics[i] = topics[i] .. "/" .. mobile.imei()
            end
        end
        return topics
    end

    if type(sub) == "string" then
        local sub_list = parseTopicList(sub)
        local topics = {}
        for i = 1, #sub_list, 2 do
            topics[sub_list[i]] = tonumber(sub_list[i + 1]) or qos
        end
        sub = topics
    end
    if type(pub) == "string" then
        pub = parseTopicList(pub)
    end

    local idx = 0
    local mqttc = mqtt.create(nil, addr, port, (ssl == 1))
    mqttc:auth(clientID, usr or "", pwd or "", cleansession)
    mqttc:keepalive(keepAlive)
    mqttc:on(function(mqtt_client, event, data, payload)
        if event == "conack" then
            sys.publish("mqtt_conack" .. cid)
        elseif event == "recv" then
            sys.publish("NET_SENT_RDY_" .. uid, "mqttrecv", data, payload, cid)
        elseif event == "disconnect" then
            sys.publish("NET_SENT_RDY_" .. uid, "disconnect", cid)
        end
    end)

    if will and will ~= "" then
        mqttc:will(will, mobile.imei(), 1, 0)
    end

    while true do
        while not socket.adapter(socket.dft()) do
            sys.waitUntil("IP_READY", 1000)
        end

        mqttc:connect()
        local conres = sys.waitUntil("mqtt_conack" .. cid, 10000)
        if mqttc:ready() and conres then
            log.info("create", "MQTT连接成功", addr, port)
            datalink[cid] = true
            sys.publish("CLOUD_CONNECTED")

            if mqttc:subscribe(sub, qos) then
                log.info("create", "MQTT订阅成功")
                -- 发布登录消息
                if pub and #pub > 0 then
                    mqttc:publish(pub[1], json.encode({imei=mobile.imei(), iccid=mobile.iccid(), ver=_G.VERSION}), tonumber(pub[2]) or qos, retain)
                end

                while true do
                    local ret, topic, data, payload, recid = sys.waitUntil("NET_SENT_RDY_" .. uid, keepAlive * 1000)
                    if ret and topic ~= "mqttrecv" and topic ~= "disconnect" then
                        -- 有数据要发送
                        local pub_topic = pub and pub[1] or ""
                        local pub_qos = tonumber(pub and pub[2]) or qos
                        if not mqttc:publish(pub_topic, data, pub_qos, retain) then
                            break
                        end
                    elseif ret and topic == "mqttrecv" and recid == cid then
                        log.info("create", "MQTT收到消息", data, payload)
                        -- 统一通过 REMOTE_COMMAND 分发到 remote.lua
                        sys.publish("REMOTE_COMMAND", {command = payload, topic = data, raw = payload})
                    elseif ret == false then
                        -- 超时，发送心跳
                        -- mqtt keepalive 自动处理，无需额外操作
                    elseif ret and topic == "disconnect" then
                        if data == cid then break end
                    end
                end
            end
        else
            log.info("create", "MQTT连接服务器失败")
        end

        datalink[cid] = false
        mqttc:disconnect()
        sys.wait((2 * idx) * 1000)
        if idx > 9 then
            mobile.flymode(0, true)
            mobile.flymode(1, true)
            sys.wait(1000)
            mobile.flymode(0, false)
            mobile.flymode(1, false)
            idx = 1
        else
            idx = idx + 1
        end
    end
end

---------------------------------------------------------- AirCloud ----------------------------------------------------------
local function aircloud_heart()
    local scell = mobile.scell()
    local band
    if scell and scell.earfcn then
        local e = scell.earfcn
        if e <= 599 then band = 1
        elseif e <= 1949 then band = 3
        elseif e <= 2649 then band = 5
        elseif e <= 3449 then band = 7
        elseif e <= 3799 then band = 8
        elseif e <= 6449 then band = 20
        elseif e <= 38249 then band = 38
        elseif e <= 38649 then band = 39
        elseif e <= 39649 then band = 40
        elseif e <= 41589 then band = 41 end
    end
    return json.encode({csq=mobile.csq(), eci=mobile.eci(), rsrp=mobile.rsrp(), band=band})
end

local function aircloudTask(cid, prot, keepAlive, timeout, uid, ssl, qos)
    cid, keepAlive, timeout, uid = cid or 1, keepAlive or 300, timeout, uid
    qos = qos or 0

    -- 记录上次发送数据的时间（毫秒级）
    local last_send_time = 0

    -- TLV 直发通道：active_mode 构造的 TLV 字段数组，直接 excloud.send
    -- 订阅在连接前就注册，避免 active_mode 先 publish 导致消息丢失
    sys.subscribe("AIRCLOUD_SEND_" .. cid, function(tlv_data)
        if type(tlv_data) == "table" and #tlv_data > 0 then
            log.info("create", "收到 AIRCLOUD_SEND_", cid, " TLV字段数:", #tlv_data)
            local ok, err = excloud.send(tlv_data, false)
            log.info("create", "TLV发送结果", ok, err)
            if ok then
                last_send_time = mcu.ticks()
            end
        end
    end)

    -- 等待网络
    while not socket.adapter(socket.dft()) do
        sys.waitUntil("IP_READY", 1000)
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
            log.info("create", "认证结果", data.success and "成功" or "失败")
        elseif event == "message" then
            for _, tlv in ipairs(data.tlvs) do
                -- 所有数据统一以 JSON 格式通过 REMOTE_COMMAND 分发
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
    local transport = (prot == "mqtt") and "mqtt" or "tcp"
    local setup_params = {
        device_type = 1,
        use_getip = true,
        transport = transport,
        auto_reconnect = true,
        reconnect_interval = 10,
        max_reconnect = 5,
        timeout = 30,
        mtn_log_enabled = true,
        mtn_log_blocks = 2,
        mtn_log_write_way = excloud.MTN_LOG_CACHE_WRITE
    }
    if transport == "mqtt" then setup_params.qos = qos end

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

    -- AirCloud 通道仅走 TLV 直发（AIRCLOUD_SEND），业务数据不再通过 RANDOM_DATA(json) 上报
    -- 主循环仅负责心跳保活
    while true do
        sys.wait(keepAlive * 1000)
        local now = mcu.ticks()
        -- 如果上次有数据上报的时间在心跳间隔内，说明数据上报已保活，跳过心跳
        if now - last_send_time >= keepAlive * 1000 then
            -- 确实长时间没发数据了，发送心跳保活
            excloud.send({{field_meaning = excloud.FIELD_MEANINGS.RANDOM_DATA, data_type = excloud.DATA_TYPES.ASCII, value = aircloud_heart()}}, false)
            last_send_time = now
        end
    end
end

---------------------------------------------------------- 连接分发 ----------------------------------------------------------
local function connect(conf)
    -- 等待网络
    while not socket.adapter(socket.dft()) do
        sys.waitUntil("IP_READY", 1000)
    end

    for k, v in pairs(conf or {}) do
        if v[1] and v[1]:upper() == "SOCKET" then
            local taskName = "DTU_" .. tostring(k)
            -- 服务端格式: ["socket", prot, ping, timeout, addr, port, uid, intervalTime(废弃), ssl]
            -- 跳过 v[8] (废弃的 intervalTime)，v[9] 才是 ssl
            local args = {v[2], v[3], v[4], v[5], v[6], v[7], v[9]}
            log.warn("create", "启动 TCP/UDP 连接")
            sys.taskInitEx(tcpTask, taskName, function() end, taskName, k, unpack(args))
        elseif v[1] and v[1]:upper() == "MQTT" then
            local taskName = "DTU_" .. tostring(k)
            -- 服务端格式: ["mqtt", keepAlive, timeout, addr, port, usr, pwd, cleansession, sub, pub, qos, retain, uid, clientID, addImei, ssl, will]
            -- v[15]=addImei(为1时主题追加IMEI), v[16]=ssl, v[17]=will
            local args = {v[2], v[3], v[4], v[5], v[6], v[7], v[8], v[9], v[10], v[11], v[12], v[13], v[14], v[15], v[16], v[17]}
            log.warn("create", "启动 MQTT 连接")
            sys.taskInitEx(mqttTask, taskName, function() end, k, unpack(args))
        elseif v[1] and v[1]:upper() == "AIRCLOUD" then
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
