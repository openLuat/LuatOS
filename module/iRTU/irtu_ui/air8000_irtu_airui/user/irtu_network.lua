local network = {}

local libnet = require "libnet"
local dtulib = require "dtulib"
local excloud = require "excloud"
local lbsLoc = require "lbsLoc"

local driver = require "irtu_driver"
local config = require "irtu_config"

local datalink = {}

local function conver(str)
    if str:match("function(.+)end") then
        return loadstring(str:match("function(.+)end"))()
    end
    local hex = str:sub(1, 2):lower() == "0x"
    str = hex and str:sub(3, -1) or str
    local tmp = dtulib.split(str, "|")
    local tmpda1, tmpdata = 0
    for idx = 1, #tmp do
        tmpdata = tmp[idx]:lower()
        if tmpdata == "sn" then
            tmpda1 = 1
            tmp[idx] = hex and (mobile.sn():toHex()) or mobile.sn()
        elseif tmpdata == "imei" then
            tmpda1 = 1
            tmp[idx] = hex and (mobile.imei():toHex()) or mobile.imei()
        elseif tmpdata == "muid" then
            tmpda1 = 1
            tmp[idx] = hex and (mobile.muid():toHex()) or mobile.muid()
        elseif tmpdata == "imsi" then
            tmpda1 = 1
            tmp[idx] = hex and (mobile.imsi():toHex()) or mobile.imsi()
        elseif tmpdata == "iccid" then
            tmpda1 = 1
            tmp[idx] = hex and (mobile.iccid():toHex()) or mobile.iccid()
        elseif tmpdata == "csq" then
            tmpda1 = 1
            tmp[idx] = hex and string.format("%02X", mobile.csq()) or tostring(mobile.csq())
        elseif idx > 1 and tmpdata == tmp[idx] and tmpda1 ~= 1 then
            tmp[idx] = "|" .. tmp[idx]
        end
    end
    return hex and dtulib.fromHexnew(table.concat(tmp)) or table.concat(tmp)
end

local function loginMsg(str)
    if not str then return nil end
    if str.type == 0 then
        return nil
    elseif str.type == 1 then
        return json.encode({
            csq = mobile.csq(),
            imei = mobile.imei(),
            iccid = mobile.iccid(),
            ver = _G.VERSION,
        })
    elseif str.type == 3 and str.data and #(str.data) ~= 0 then
        return conver(str.data)
    else
        return nil
    end
end

local function updateDatalink(cid, value)
    datalink[cid] = value
    driver.setDatalink(cid, value)
end

local function listTopic(str, addImei, ProductKey, deviceName)
    local topics = dtulib.split(str, ";")
    if #topics == 1 and addImei == 1 then
        topics[1] = topics[1]:sub(-1, -1) == "/" and topics[1] .. mobile.imei()
            or topics[1] .. "/" .. mobile.imei()
    else
        local tmp
        for i = 1, #topics, 2 do
            tmp = dtulib.split(topics[i], "/")
            for j = 1, #tmp do
                local value = tmp[j]:lower()
                if value == "imei" then
                    tmp[j] = mobile.imei()
                elseif value == "muid" then
                    tmp[j] = mobile.muid()
                elseif value == "imsi" then
                    tmp[j] = mobile.imsi()
                elseif value == "iccid" then
                    tmp[j] = mobile.iccid()
                elseif value == "productid" or value == "{pid}" then
                    tmp[j] = ProductKey
                elseif value == "sn" then
                    tmp[j] = mobile.sn()
                elseif value == "messageid" or value == "${messageid}" then
                    tmp[j] = "+"
                elseif value == "productkey" or value == "${productkey}" or value == "${yourproductkey}" then
                    tmp[j] = ProductKey
                elseif value == "devicename" or value == "${devicename}" or value == "${deviceName}"
                    or value == "{device-name}" then
                    tmp[j] = deviceName
                end
            end
            topics[i] = table.concat(tmp, "/")
        end
    end
    return topics
end

local function aircloud_heart()
    local csq = mobile.csq()
    local eci = mobile.eci()
    local rsrp = mobile.rsrp()
    local scell = mobile.scell()
    local band
    if scell.earfcn >= 0 and scell.earfcn <= 599 then
        band = 1
    elseif scell.earfcn >= 1200 and scell.earfcn <= 1949 then
        band = 3
    elseif scell.earfcn >= 2400 and scell.earfcn <= 2649 then
        band = 5
    elseif scell.earfcn >= 2750 and scell.earfcn <= 3449 then
        band = 7
    elseif scell.earfcn >= 3450 and scell.earfcn <= 3799 then
        band = 8
    elseif scell.earfcn >= 6150 and scell.earfcn <= 6449 then
        band = 20
    elseif scell.earfcn >= 37750 and scell.earfcn <= 38249 then
        band = 38
    elseif scell.earfcn >= 38250 and scell.earfcn <= 38649 then
        band = 39
    elseif scell.earfcn >= 38650 and scell.earfcn <= 39649 then
        band = 40
    elseif scell.earfcn >= 39650 and scell.earfcn <= 41589 then
        band = 41
    end
    local heart = {
        csq = csq,
        eci = eci,
        rsrp = rsrp,
        band = band,
    }
    return json.encode(heart)
end

local function handleUplink(dwprotFnc, data, uid, reg, cid)
    if data:sub(1, 5) == "rrpc," or data:sub(1, 7) == "config," then
        local res, msg = pcall(driver.userapi, data)
        if not res then
            log.error("远程查询的API错误:", msg)
        end
        if dwprotFnc then
            res, msg = pcall(dwprotFnc, data)
            if not res then
                log.error("数据流模版错误:", msg)
            else
                res, msg = pcall(driver.userapi, msg)
                if not res then
                    log.error("远程查询的API错误:", msg)
                end
            end
        end
        return msg
    elseif dwprotFnc then
        local res, msg = pcall(dwprotFnc, data)
        if not res or not msg then
            log.error("数据流模版错误:", msg)
        else
            sys.publish("UART_SENT_RDY_" .. uid, uid, msg)
        end
    else
        sys.publish("UART_SENT_RDY_" .. uid, uid, data)
    end
end

local function tcpTask(dName, cid, pios, reg, upprot, dwprot, sockettype, prot, ping, timeout, addr, port,
                      uid, intervalTime, ssl)
    cid, prot, timeout, uid = cid or 1, prot:upper(), timeout or 120, uid or 1
    local outputSocket = {}
    local autoReturn = true
    ping = (ping and ping ~= "") and ping or "0x00"
    local dwprotFnc = dwprot and dwprot[cid] and dwprot[cid] ~= "" and
        loadstring(dwprot[cid]:match("function(.+)end"))
    local upprotFnc = upprot and upprot[cid] and upprot[cid] ~= "" and
        loadstring(upprot[cid]:match("function(.+)end"))
    local tx_buff = zbuff.create(1024)
    local rx_buff = zbuff.create(1024)
    local idx = 0
    local waitsend = 0
    local netc = socket.create(nil, dName)
    local subMessage = function(data)
        if data and data ~= "mqttrecv" and data ~= "disconnect" then
            table.insert(outputSocket, data)
            if waitsend == 0 then
                sys_send(dName, socket.EVENT, 0)
                waitsend = 1
            else
                sys.timerStart(function()
                    sys_send(dName, socket.EVENT, 0)
                end, 500)
            end
        end
    end
    sys.subscribe("NET_SENT_RDY_" .. uid, subMessage)
    local isUdp = prot == "UDP"
    local isSsl = ssl == "ssl"
    socket.debug(netc, true)
    socket.config(netc, nil, isUdp, isSsl)
    while true do
        while not socket.adapter(socket.dft()) do
            sys.waitUntil("IP_READY", 1000)
        end
        local res = libnet.waitLink(dName, 0, netc)
        local result = libnet.connect(dName, timeout * 1000, netc, addr, port)
        if result then
            idx = 0
            if autoReturn and intervalTime > 0 then
                sys.publish("AUTO_SAMPL_" .. uid)
                sys.timerLoopStart(sys.publish, intervalTime * 1000, "AUTO_SAMPL_" .. uid)
                autoReturn = false
            end
            updateDatalink(cid, true)
            local login_data = loginMsg(reg)
            if login_data then
                libnet.tx(dName, nil, netc, login_data)
            end
            while true do
                waitsend = 0
                local ok, param = libnet.wait(dName, timeout * 1000, netc)
                if not ok then break end
                if param == false then
                    local ret, _ = libnet.tx(dName, nil, netc, conver(ping))
                    if not ret then break end
                end
                local succ = socket.rx(netc, rx_buff)
                if not succ then break end
                if rx_buff:used() > 0 then
                    local data = rx_buff:toStr(0, rx_buff:used())
                    local msg = handleUplink(dwprotFnc, data, uid, reg, cid)
                    if msg and libnet.tx(dName, nil, netc, msg) == false then break end
                    rx_buff:del()
                end
                tx_buff:copy(nil, table.concat(outputSocket))
                outputSocket = {}
                if tx_buff:used() > 0 then
                    local data = tx_buff:toStr(0, tx_buff:used())
                    if upprotFnc then
                        local res, msg = pcall(upprotFnc, data)
                        if not res or not msg then
                            log.error("数据流模版错误:", msg)
                        else
                            if not libnet.tx(dName, nil, netc, msg) then break end
                        end
                    else
                        if not libnet.tx(dName, nil, netc, data) then break end
                    end
                end
                tx_buff:del()
                if tx_buff:len() > 1024 then tx_buff:resize(1024) end
                if rx_buff:len() > 1024 then rx_buff:resize(1024) end
            end
        end
        updateDatalink(cid, false)
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

local function mqttTask(cid, pios, reg, upprot, dwprot, keepAlive, timeout, addr, port, usr, pwd,
                        cleansession, sub, pub, qos, retain, uid, clientID, addImei, ssl, will,
                        idAddImei, prTopic)
    cid, keepAlive, timeout, uid = cid or 1, keepAlive or 300, timeout, uid
    qos, retain = qos or 0, retain or 0
    cleansession = cleansession == 1
    if idAddImei ~= 0 then
        clientID = clientID == "" or not clientID and mobile.imei() or mobile.imei() .. clientID
    else
        clientID = clientID == "" or not clientID and mobile.imei() or clientID
    end
    if type(sub) == "string" then
        sub = listTopic(sub, addImei, config.get().project_key, mobile.imei())
        local topics = {}
        for i = 1, #sub, 2 do
            topics[sub[i]] = tonumber(sub[i + 1]) or qos
        end
        sub = topics
    end
    if type(pub) == "string" then
        pub = listTopic(pub, addImei, config.get().project_key, mobile.imei())
    end
    local dwprotFnc = dwprot and dwprot[cid] and dwprot[cid] ~= "" and
        loadstring(dwprot[cid]:match("function(.+)end"))
    local upprotFnc = upprot and upprot[cid] and upprot[cid] ~= "" and
        loadstring(upprot[cid]:match("function(.+)end"))
    local mqttc = mqtt.create(nil, addr, port, ssl == 1)
    mqttc:auth(conver(clientID), conver(usr), conver(pwd), cleansession)
    mqttc:keepalive(keepAlive)
    local messageId = false
    mqttc:on(function(_, event, data, payload)
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
        if mqttc:ready() and conres and mqttc:subscribe(sub, qos) then
            updateDatalink(cid, true)
            if timeout > 0 then
                sys.publish("AUTO_SAMPL_" .. uid)
                sys.timerLoopStart(sys.publish, timeout * 1000, "AUTO_SAMPL_" .. uid)
            end
            if loginMsg(reg) then
                mqttc:publish(pub[1], loginMsg(reg), tonumber(pub[2]) or qos, retain)
            end
            while true do
                local ret, topic, data, payload, recid = sys.waitUntil("NET_SENT_RDY_" .. uid,
                    (keepAlive or 180) * 1000)
                if ret and topic ~= "mqttrecv" and topic ~= "disconnect" then
                    local publishTopic = pub[1]
                    local payloadToSend = topic
                    if upprotFnc then
                        local res, msg = pcall(upprotFnc, topic)
                        if res and msg then
                            publishTopic = pub[(msg.index or 1)]
                            payloadToSend = msg
                        end
                    end
                    if not mqttc:publish(publishTopic, payloadToSend, tonumber(pub[2]) or qos, retain) then
                        break
                    end
                    messageId = false
                elseif ret and topic == "mqttrecv" and recid == cid then
                    messageId = data:match(".+/rrpc/request/(%d+)")
                    if payload:sub(1, 5) == "rrpc," or payload:sub(1, 7) == "config," then
                        local res, msg = pcall(driver.userapi, payload)
                        if not res then log.error("远程查询的API错误:", msg) end
                        pcall(function()
                            if dwprotFnc then
                                local ok, msg2 = pcall(dwprotFnc, payload)
                                if ok and msg2 then
                                    local res, msg3 = pcall(driver.userapi, msg2)
                                    if res then
                                        mqttc:publish(pub[1], msg3, tonumber(pub[2]) or qos, retain)
                                    end
                                end
                            else
                                mqttc:publish(pub[1], msg, tonumber(pub[2]) or qos, retain)
                            end
                        end)
                    elseif dwprotFnc then
                        local ok, msg = pcall(dwprotFnc, payload, data)
                        if ok and msg then
                            sys.publish("UART_SENT_RDY_" .. uid, uid, msg)
                        end
                    else
                        sys.publish("UART_SENT_RDY_" .. uid, uid, payload)
                    end
                elseif ret == false then
                    log.warn("等待超时")
                elseif ret and topic == "disconnect" then
                    break
                else
                    break
                end
            end
        end
        updateDatalink(cid, false)
        mqttc:disconnect()
        sys.wait(2000)
    end
end

local function aircloudTask(cid, pios, reg, upprot, dwprot, tasktype, prot, keepAlive, timeout, authkey,
                           uid, ssl, qos)
    cid, keepAlive, timeout, uid = cid or 1, keepAlive or 300, timeout, uid
    qos = qos or 0
    local dwprotFnc = dwprot and dwprot[cid] and dwprot[cid] ~= "" and
        loadstring(dwprot[cid]:match("function(.+)end"))
    local upprotFnc = upprot and upprot[cid] and upprot[cid] ~= "" and
        loadstring(upprot[cid]:match("function(.+)end"))
    excloud.on(function(event, data)
        if event == "connect_result" then
            if data.success then
                updateDatalink(cid, true)
            end
        elseif event == "message" then
            for _, tlv in ipairs(data.tlvs) do
                if tlv.field == excloud.FIELD_MEANINGS.CONTROL_COMMAND then
                    if dwprotFnc then
                        local res, msg = pcall(dwprotFnc, tlv.value, tlv.field)
                        if res and msg then
                            sys.publish("UART_SENT_RDY_" .. uid, uid, msg)
                        end
                    else
                        sys.publish("UART_SENT_RDY_" .. uid, uid, tlv.value)
                    end
                elseif tlv.field == excloud.FIELD_MEANINGS.IRTU_DOWN then
                    if tlv.value:sub(1, 5) == "rrpc," or tlv.value:sub(1, 7) == "config," then
                        local res, msg = pcall(driver.userapi, tlv.value)
                        if res and msg then
                            sys.publish("NET_SENT_RDY_" .. uid, msg)
                        end
                    end
                else
                    if dwprotFnc then
                        local res, msg = pcall(dwprotFnc, tlv.value, tlv.field)
                        if res and msg then
                            sys.publish("UART_SENT_RDY_" .. uid, uid, msg)
                        end
                    else
                        sys.publish("UART_SENT_RDY_" .. uid, uid, tlv.value)
                    end
                end
            end
        elseif event == "disconnect" then
            updateDatalink(cid, false)
        end
    end)
    sys.wait(1000)
    local ok, err_msg = excloud.setup({
        device_type = 1,
        use_getip = true,
        auth_key = authkey,
        transport = prot,
        auto_reconnect = true,
        reconnect_interval = 10,
        max_reconnect = 5,
        timeout = 30,
        qos = qos,
        mtn_log_enabled = true,
        mtn_log_blocks = 2,
        mtn_log_write_way = excloud.MTN_LOG_CACHE_WRITE,
    })
    if not ok then
        log.info("初始化失败: " .. err_msg)
        return
    end
    if not excloud.open() then
        log.info("开启excloud服务失败: " .. err_msg)
        return
    end
    local outputSocket = {}
    local subMessage = function(data)
        if data then
            table.insert(outputSocket, data)
            sys.publish("SEND_DATA")
        end
    end
    sys.subscribe("NET_SENT_RDY_" .. uid, subMessage)
    while true do
        local ret = sys.waitUntil("SEND_DATA", (keepAlive * 1000))
        if not ret then
            excloud.send({
                {
                    field_meaning = excloud.FIELD_MEANINGS.RANDOM_DATA,
                    data_type = excloud.DATA_TYPES.ASCII,
                    value = aircloud_heart(),
                },
            }, false)
        else
            while #outputSocket > 0 do
                local data = table.remove(outputSocket, 1)
                if data:sub(1, 5) == "rrpc," or data:sub(1, 7) == "config," then
                    excloud.send({
                        {
                            field_meaning = excloud.FIELD_MEANINGS.IRTU_UP,
                            data_type = excloud.DATA_TYPES.ASCII,
                            value = data,
                        },
                    }, false)
                else
                    if upprotFnc then
                        local res, msg = pcall(upprotFnc, data)
                        if res and msg then
                            excloud.send({
                                {
                                    field_meaning = excloud.FIELD_MEANINGS.RANDOM_DATA,
                                    data_type = excloud.DATA_TYPES.ASCII,
                                    value = msg,
                                },
                            }, false)
                        end
                    else
                        excloud.send({
                            {
                                field_meaning = excloud.FIELD_MEANINGS.RANDOM_DATA,
                                data_type = excloud.DATA_TYPES.ASCII,
                                value = data,
                            },
                        }, false)
                    end
                end
            end
        end
    end
end

local function startNetworkTasks()
    local dtu = config.get()
    for cid, v in pairs(dtu.conf or {}) do
        if v[1] then
            local protocol = v[1]:upper()
            if protocol == "SOCKET" then
                local taskName = "DTU_" .. cid
                sys.taskInitEx(tcpTask, taskName, nil, taskName, cid, driver.pios, dtu.reg,
                    dtu.upprot, dtu.dwprot, unpack(v))
            elseif protocol == "MQTT" then
                sys.taskInit(mqttTask, cid, driver.pios, dtu.reg, dtu.upprot, dtu.dwprot,
                    unpack(v, 2))
            elseif protocol == "AIRCLOUD" then
                local taskName = "DTU_" .. cid
                sys.taskInitEx(aircloudTask, taskName, nil, cid, driver.pios, dtu.reg,
                    dtu.upprot, dtu.dwprot, unpack(v))
            end
        end
    end
end

local function waitForParam()
    while true do
        while not socket.adapter(socket.dft()) do
            sys.waitUntil("IP_READY", 1000)
        end
        sys.waitUntil("DTU_PARAM_READY", 120000)
        startNetworkTasks()
    end
end

function network.start()
    sys.taskInit(waitForParam)
end

return network

