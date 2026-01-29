create = {}

libnet = require "libnet"
dtulib = require "dtulib"

excloud= require ("excloud")
local lbsLoc = require("lbsLoc")
local default = require("default")
local dtu
local audio_uid="a"
local audio_cid="a"

local datalink, defChan = {}, 1
-- 定时采集任务的参数
local interval, samptime = { 0, 0, 0 }, { 0, 0, 0 }
interval[uart.VUART_0], samptime[uart.VUART_0] = 0, 0
-- 获取经纬度
local latdata, lngdata = 0, 0

local output, input = {}, {}

sys.subscribe("audio_result", function(data)
    if audio_uid~="a" and audio_cid~="a" then
        sys.publish("NET_SENT_RDY_" .. audio_uid, "audioresult_"..audio_cid,data)
        audio_uid="a"
        audio_cid="a"
    end
end)

-- 用户读取ADC
function create.getADC(id)
    adc.open(id)
    local adcValue = adc.get(id)
    adc.close(id)
    if adcValue ~= 0xFFFF then
        return adcValue
    end
end

function create.getDatalink(cid)
    if tonumber(cid) then
        return datalink[cid]
    else
        return datalink[defChan]
    end
end

local function netCB(msg)
    log.info("未处理消息", msg[1], msg[2], msg[3], msg[4])
end

-- 获取纬度
function create.getLat()
    return latdata
end

-- 获取经度
function create.getLng()
    return lngdata
end

-- 获取实时经纬度
function create.getRealLocation()
    lbsLoc.request(function(result, lat, lng, addr, time, locType)
        if result then
            latdata = lat
            lngdata = lng
        end
    end)
    return latdata, lngdata
end

--- 用户串口和远程调用的API接口
-- @string str：执行API的命令字符串
-- @retrun str : 处理结果字符串
function create.userapi(str)
    local t = str:match("(.+)\r\n") and dtulib.split(str:match("(.+)\r\n"), ',') or dtulib.split(str, ',')
    local first = table.remove(t, 1)
    local second = table.remove(t, 1) or ""
    if tonumber(second) and tonumber(second) > 0 and tonumber(second) < 8 then
        return cmd[first]["pipe"](t, second) .. "\r\n"
    elseif cmd[first][second] then
        return cmd[first][second](t, str) .. "\r\n"
    else
        return "ERROR\r\n"
    end
end

---------------------------------------------------------- DTU的网络任务部分 ----------------------------------------------------------
local function conver(str)
    if str:match("function(.+)end") then
        return loadstring(str:match("function(.+)end"))()
    end
    local hex = str:sub(1, 2):lower() == "0x"
    str = hex and str:sub(3, -1) or str
    local tmp = dtulib.split(str,"|")
    local tmpda1=0
    for v = 1, #tmp do
        local tmpdata=tmp[v]:lower()
        
        if tmp[v]:lower() == "sn" then
            tmpda1=1
            tmp[v] = hex and (mobile.sn():toHex()) or mobile.sn()
        end
        if tmp[v]:lower() == "imei" then
            tmpda1=1
            tmp[v] = hex and (mobile.imei():toHex()) or mobile.imei()
        end
        if tmp[v]:lower() == "muid" then
            tmpda1=1
            tmp[v] = hex and (mobile.muid():toHex()) or mobile.muid()
        end
        if tmp[v]:lower() == "imsi" then
            tmpda1=1
            tmp[v] = hex and (mobile.imsi():toHex()) or mobile.imsi()
        end
        if tmp[v]:lower() == "iccid" then
            tmpda1=1
            tmp[v] = hex and (mobile.iccid():toHex()) or mobile.iccid()
        end
        if tmp[v]:lower() == "csq" then
            tmpda1=1
            tmp[v] = hex and string.format("%02X", mobile.csq()) or tostring(mobile.csq())
        end
        if tmpdata==tmp[v] and v>1  then
            if tmpda1~=1 then
                tmp[v] = "|"..tmp[v]
            end
         end
    end
    return hex and dtulib.fromHexnew((table.concat(tmp))) or table.concat(tmp)
end

-- 登陆报文
local function loginMsg(str)
    if str.type == 0 then
        return nil
    elseif str.type == 1 then
        return json.encode({
            csq = mobile.csq(),
            imei = mobile.imei(),
            iccid = mobile.iccid(),
            ver = _G.VERSION
        })
    elseif str.type == 3 and str.data and #(str.data) ~= 0  then
         return conver(str.data)
    else
        return nil
    end
end
---------------------------------------------------------- SOKCET 服务 ----------------------------------------------------------
local function tcpTask(dName, cid, pios, reg,upprot, dwprot, sockettype,prot, ping, timeout, addr, port, uid,intervalTime, ssl)
    cid, prot, timeout, uid = cid or 1, prot:upper(), timeout or 120, uid or 1
    local outputSocket = {}
    local autoReturn=true
    if not ping or ping == "" then
        ping = "0x00"
    end
    local dwprotFnc = dwprot and dwprot[cid] and dwprot[cid] ~= "" and loadstring(dwprot[cid]:match("function(.+)end"))
    local upprotFnc = upprot and upprot[cid] and upprot[cid] ~= "" and loadstring(upprot[cid]:match("function(.+)end"))
    local tx_buff = zbuff.create(1024)
    local rx_buff = zbuff.create(1024)
    local idx = 0
    -- local dName = "SOCKET" .. cid
    local waitsend=0
    local netc = socket.create(nil, dName)
    local subMessage = function(data,data2)
        if data then
            if data~="mqttrecv" and data~="disconnect"then
                if data:match("GPSCID_") then
                    -- log.info("是GPS发过来的消息")
                    if data== "GPSCID_"..cid then
                        -- log.info("匹配CID成功",cid)
                        table.insert(outputSocket, data2)
                        if waitsend==0 then
                            sys_send(dName, socket.EVENT, 0)
                            waitsend=1
                        else
                            log.info("太快了，晚500ms发")
                            sys.timerStart(function ()
                            sys_send(dName, socket.EVENT, 0)
                            end,500)
                        end
                    else
                        -- log.info("匹配CID失败",data)
                    end
                elseif data:match("audioresult_") then
                    if data== "audioresult_"..cid then
                        -- log.info("匹配CID成功",cid)
                        table.insert(outputSocket, data2)
                        if waitsend==0 then
                            sys_send(dName, socket.EVENT, 0)
                            waitsend=1
                        else
                            log.info("太快了，晚500ms发")
                            sys.timerStart(function ()
                            sys_send(dName, socket.EVENT, 0)
                            end,500)
                        end
                    else
                        -- log.info("匹配CID失败",data)
                    end
                else
                    table.insert(outputSocket, data)
                    if waitsend==0 then
                        sys_send(dName, socket.EVENT, 0)
                        waitsend=1
                    else
                        log.info("太快了，晚500ms发")
                        sys.timerStart(function ()
                        sys_send(dName, socket.EVENT, 0)
                        end,500)
                    end
                end
            end
        end
    end
    sys.subscribe("NET_SENT_RDY_" .. uid, subMessage)

    local isUdp = prot == "UDP" and true or false
    local isSsl = ssl == "ssl" and true or false
    log.info("DNAME", dName, isUdp, isSsl, addr, prot, ping, port,uid,reg,intervalTime, ssl, login)
    log.info("DNAME1",login,type(login))
    log.info("BSP",rtos.bsp())
    socket.debug(netc, true)
    socket.config(netc, nil, isUdp, isSsl)
    while true do
        -- 如果当前时间点设置的默认网卡还没有连接成功，一直在这里循环等待
    while not socket.adapter(socket.dft()) do
        log.warn("tcp_client_main_task_func", "wait IP_READY", socket.dft())
        -- 在此处阻塞等待默认网卡连接成功的消息"IP_READY"
        -- 或者等待1秒超时退出阻塞等待状态;
        -- 注意：此处的1000毫秒超时不要修改的更长；
        -- 因为当使用exnetif.set_priority_order配置多个网卡连接外网的优先级时，会隐式的修改默认使用的网卡
        -- 当exnetif.set_priority_order的调用时序和此处的socket.adapter(socket.dft())判断时序有可能不匹配
        -- 此处的1秒，能够保证，即使时序不匹配，也能1秒钟退出阻塞状态，再去判断socket.adapter(socket.dft())
        sys.waitUntil("IP_READY", 1000)
    end

        local res = libnet.waitLink(dName, 0, netc)
        local result = libnet.connect(dName, timeout * 1000, netc, addr, port)
        if result then
            idx = 0
            log.info("tcp连接成功", dName, addr, port)
            if autoReturn then
                if intervalTime>0 then
                    sys.publish("AUTO_SAMPL_"..uid)
                    sys.timerLoopStart(sys.publish, intervalTime * 1000, "AUTO_SAMPL_" .. uid)
                    autoReturn=false
                end
            else
                -- log.info("已经运行了")
            end
            -- 登陆报文
            datalink[cid] = true
            local login_data = login or loginMsg(reg)
            if login_data then
                log.info("发送登录报文", login_data:toHex())
                libnet.tx(dName, nil, netc, login_data)
            end
            while true do
                log.info("循环等待消息")
                log.info(",cid", cid, ",UID", uid)
                waitsend=0
                local result, param = libnet.wait(dName, timeout * 1000, netc)
                log.info("result1",result,param)
                if not result then
                    log.info("网络异常", result, param)
                    break
                end
                if param == false then
                    local result, param = libnet.tx(dName, nil, netc, conver(ping))
                    if not result then
                        break
                    end
                end
                local succ, param, _, _ = socket.rx(netc, rx_buff)
                if not succ then
                    log.info("服务器断开了", succ, param, addr, port)
                    break
                end
                if rx_buff:used() > 0 then
                    log.info("收到服务器数据，长度", rx_buff:used())
                    local data = rx_buff:toStr(0, rx_buff:used())
                    if data:sub(1, 5) == "rrpc," or data:sub(1, 7) == "config," then
                        audio_uid=uid
                        audio_cid=cid
                        local res, msg = pcall(create.userapi, data, pios)
                        if not res then
                            log.error("远程查询的API错误:", msg)
                        end
                        if dwprotFnc then -- 转换为用户自定义报文
                            res, msg = pcall(dwprotFnc, data)
                            if not res then
                                log.error("数据流模版错误:", msg)
                            end
                            res, msg = pcall(create.userapi, msg, pios)
                            if not res then
                                log.error("远程查询的API错误:", msg)
                            end
                        end
                        if not libnet.tx(dName, nil, netc, msg) then
                            break
                        end
                    elseif  dwprotFnc then -- 转换用户自定义报文
                        local res, msg = pcall(dwprotFnc, data)
                        if not res or not msg then
                            log.error("数据流模版错误:", msg)
                        else
                            sys.publish("UART_SENT_RDY_" .. uid, uid, res and msg or data)
                        end
                    else -- 默认不转换
                        sys.publish("UART_SENT_RDY_" .. uid, uid, data)
                    end
                    -- uart.tx(uart_id, rx_buff)
                    log.info("RXBUFF1", rx_buff)
                    rx_buff:del()
                    log.info("RXBUFF2", rx_buff)
                end
                tx_buff:copy(nil, table.concat(outputSocket))
                outputSocket = {}
                if tx_buff:used() > 0 then
                    local data = tx_buff:toStr(0, tx_buff:used())
                    if  upprotFnc then -- 转换为用户自定义报文
                        local res, msg = pcall(upprotFnc, data)
                        if not res or not msg then
                            log.error("数据流模版错误:", msg)
                        else
                            log.info("RES", res, msg)
                            local succ, param = libnet.tx(dName, nil, netc, res and msg or data)
                            -- TODO 缓冲区满的情况
                            if not succ then
                                log.info("tcp", "tx失败,退出循环", dName, addr, port)
                                break
                            end
                        end
                    else -- 默认不转换
                        local succ, param = libnet.tx(dName, nil, netc, data)
                        -- TODO 缓冲区满的情况
                        if not succ then
                            log.info("tcp", "tx失败,退出循环", dName, addr, port)
                            break
                        end
                    end
                else
                    log.info("tcp", "无数据待发送", dName, addr, port)
                    --break
                end
                tx_buff:del()
                -- log.info("TXBUFF2",tx_buff:read())
                --log.info("TXBUFF1",tx_buff:used())
                if tx_buff:len() > 1024 then
                    tx_buff:resize(1024)
                end
                if rx_buff:len() > 1024 then
                    rx_buff:resize(1024)
                end
                log.info("RESULT", result, ",DATA", data, ",PARAM", param,  ",cid", cid, ",UID", uid)
            end
        else
            log.info("tcp连接失败了", dName, addr, port)
        end
        log.info("关闭tcp链接", dName, addr, port)
        datalink[cid] = false
        libnet.close(dName, 5000, netc)
        sys.wait((2 * idx) * 1000)
        if idx>9 then
            mobile.flymode(0,true)
            mobile.flymode(1,true)
            sys.wait(1000)
            mobile.flymode(0, false)
            mobile.flymode(1, false)
            idx=1
        else
            idx=idx + 1
        end
    end
end
---------------------------------------------------------- MQTT 服务 ----------------------------------------------------------
local function listTopic(str, addImei, ProductKey, deviceName)
    local topics = dtulib.split(str, ";")
    if #topics == 1 and  addImei == 1 then
        topics[1] = topics[1]:sub(-1, -1) == "/" and topics[1] .. mobile.imei() or topics[1] .. "/" .. mobile.imei()
    else
        local tmp = {}
        for i = 1, #topics, 2 do
            tmp = dtulib.split(topics[i], "/")
            for key, value in pairs(tmp) do
                log.info("KEY2", key, value)
            end
            for v = 1, #tmp do
                if tmp[v]:lower() == "imei" then
                    tmp[v] = mobile.imei()
                end
                if tmp[v]:lower() == "muid" then
                    tmp[v] = mobile.muid()
                end
                if tmp[v]:lower() == "imsi" then
                    tmp[v] = mobile.imsi()
                end
                if tmp[v]:lower() == "iccid" then
                    tmp[v] = mobile.iccid()
                end
                if tmp[v]:lower() == "productid" or tmp[v]:lower() == "{pid}" then
                    tmp[v] = ProductKey
                end
                if tmp[v]:lower() == "sn" then
                    tmp[v] = hex and (mobile.sn():toHex()) or mobile.sn()
                end
                if tmp[v]:lower() == "messageid" or tmp[v]:lower() == "${messageid}" then
                    tmp[v] = "+"
                end
                if tmp[v]:lower() == "productkey" or tmp[v]:lower() == "${productkey}" or tmp[v]:lower() ==
                    "${yourproductkey}" then
                    tmp[v] = ProductKey
                end
                if tmp[v]:lower() == "devicename" or tmp[v]:lower() == "${devicename}" or tmp[v]:lower() ==
                    "${yourdevicename}" or tmp[v]:lower() == "{device-name}" or tmp[v]:lower() == "${deviceName}" then
                    tmp[v] = deviceName
                end
            end
            topics[i] = table.concat(tmp, "/")
            log.info("订阅或发布主题:", i, topics[i])
        end
    end
    return topics
end

local function mqttTask(cid, pios, reg, upprot, dwprot, keepAlive, timeout, addr, port, usr, pwd,
                        cleansession, sub, pub, qos, retain, uid, clientID, addImei, ssl, will, idAddImei, prTopic, cert)
    cid, keepAlive, timeout, uid = cid or 1, keepAlive or 300, timeout, uid
    qos, retain =  qos or 0, retain or 0
    cleansession=cleansession==1 and true or false
    local autoReturn=true
    if idAddImei == 0 then
        clientID = (clientID == "" or not clientID) and mobile.imei() or clientID
    else
        clientID = (clientID == "" or not clientID) and mobile.imei() or mobile.imei() .. clientID
    end
    if type(sub) == "string" then
        sub = listTopic(sub, addImei)
        local topics = {}
        for i = 1, #sub,2 do
            topics[sub[i]] = tonumber(sub[i + 1]) or qos
            log.info("TOPICS", topics[sub[i]])
        end
        sub = topics
    end
    if type(pub) == "string" then
        pub = listTopic(pub, addImei)
    end
    local dwprotFnc = dwprot and dwprot[cid] and dwprot[cid] ~= "" and loadstring(dwprot[cid]:match("function(.+)end"))
    local upprotFnc = upprot and upprot[cid] and upprot[cid] ~= "" and loadstring(upprot[cid]:match("function(.+)end"))

    -- log.info("MQTT HOST:PORT", addr, port)
    -- log.info("MQTT clientID,user,pwd", clientID, conver(usr), conver(pwd))
    local idx = 0
    local mqttc = mqtt.create(nil, addr, port, (ssl == 1 and true or false))
    -- 是否为ssl加密连接,默认不加密,true为无证书最简单的加密，table为有证书的加密
    mqttc:auth(conver(clientID), conver(usr), conver(pwd),cleansession)
    log.info("KEEPALIVE", keepAlive)
    mqttc:keepalive(keepAlive)
    mqttc:on(function(mqtt_client, event, data, payload) -- mqtt回调注册
        -- 用户自定义代码，按event处理
        log.info("mqtt", "event", event, mqtt_client, data, payload)
        if event == "conack" then
            sys.publish("mqtt_conack"..cid)
        elseif event == "recv" then -- 服务器下发的数据
            log.info("mqtt", "downlink", "topic", data, "payload", payload)
            sys.publish("NET_SENT_RDY_" .. uid, "mqttrecv", data, payload,cid)
            -- 这里继续加自定义的业务处理逻辑
        elseif event == "sent" then -- publish成功后的事件
            log.info("mqtt", "sent", "pkgid", data)
        elseif event == "disconnect" then
            -- 非自动重连时,按需重启mqttc
            -- mqtt_client:connect()
            sys.publish("NET_SENT_RDY_" ..  uid,"disconnect",cid)
        end
    end)
    if not will or will == "" then
        will = nil
    else
        mqttc:will(will, mobile.imei(), 1, 0)
    end

    while true do
        -- log.info("chysTest.sendTestTelemetry1", sendTestTelemetryCount, rtos.version(),
        --     "mem.lua", rtos.meminfo("lua"));
        local messageId = false
        -- 如果当前时间点设置的默认网卡还没有连接成功，一直在这里循环等待
    while not socket.adapter(socket.dft()) do
        log.warn("tcp_client_main_task_func", "wait IP_READY", socket.dft())
        -- 在此处阻塞等待默认网卡连接成功的消息"IP_READY"
        -- 或者等待1秒超时退出阻塞等待状态;
        -- 注意：此处的1000毫秒超时不要修改的更长；
        -- 因为当使用exnetif.set_priority_order配置多个网卡连接外网的优先级时，会隐式的修改默认使用的网卡
        -- 当exnetif.set_priority_order的调用时序和此处的socket.adapter(socket.dft())判断时序有可能不匹配
        -- 此处的1秒，能够保证，即使时序不匹配，也能1秒钟退出阻塞状态，再去判断socket.adapter(socket.dft())
        sys.waitUntil("IP_READY", 1000)
    end
        mqttc:connect()
        -- local mqttc = mqtt.client(clientID, keepAlive, conver(usr), conver(pwd), cleansession, will, "3.1.1")
        local conres = sys.waitUntil("mqtt_conack"..cid, 10000)
        if mqttc:ready() and conres then
            log.info("mqtt连接成功")
            datalink[cid] = true
            -- 初始化订阅主题
            -- sub1={["/luatos/1234567"]=1,["/luatos/12345678"]=2}
            if mqttc:subscribe(sub, qos) then
                -- local a=mqttc:subscribe(topic3,1)
                log.info("mqtt订阅成功")
                if autoReturn then
                    if timeout>0 then
                        sys.publish("AUTO_SAMPL_"..uid)
                        sys.timerLoopStart(sys.publish, timeout * 1000, "AUTO_SAMPL_" .. uid)
                        autoReturn=false
                    end
                else
                    log.info("已经运行了")
                end
                -- mqttc:publish(pub, "hello,server", qos)
                if loginMsg(reg) then
                    mqttc:publish(pub[1], loginMsg(reg), tonumber(pub[2]) or qos, retain)
                end
                -- if loginMsg(reg) then mqttc:publish(sub, "hello,server", 1) end
                while true do
                    local ret, topic, data, payload,recid = sys.waitUntil("NET_SENT_RDY_" .. uid,
                        (keepAlive or 180) * 1000)
                    log.info("RET", ret, topic, data, payload,recid)
                    if ret and topic ~= "mqttrecv" and topic~="disconnect" then
                        if topic:match("GPSCID_") then
                            -- log.info("是GPS发过来的消息")
                            if topic== "GPSCID_"..cid then
                                if  upprotFnc then -- 转换为用户自定义报文
                                    local res, msg, index = pcall(upprotFnc, data)
                                    if not res or not msg then
                                        log.error("数据流模版错误:", msg)
                                    else
                                        index = tonumber(index) or 1
                                        local pub_topic = (pub[index]:sub(-1, -1) == "+" and messageId) and
                                            pub[index]:sub(1, -2) .. messageId or pub[index]
                                        log.info("-----发布的主题:", pub_topic)
                                        if not mqttc:publish(pub_topic, res and msg or data, tonumber(pub[index + 1]) or qos,
                                                retain) then
                                            break
                                        end
                                    end
                                else
                                    local pub_topic = (pub[1]:sub(-1, -1) == "+" and messageId) and pub[1]:sub(1, -2) ..
                                        messageId or pub[1]
                                    log.info("-----发布的主题:", pub_topic)
                                    if not mqttc:publish(pub_topic, data, tonumber(pub[2]) or qos, retain) then
                                        break
                                    end
                                end
                                messageId = false
                                log.info('The client actively reports status information.')
                            else
                                -- log.info("匹配CID失败",data)
                            end
                        elseif topic:match("audioresult_") then
                            -- log.info("是GPS发过来的消息")
                            if topic== "audioresult_"..cid then
                                if  upprotFnc then -- 转换为用户自定义报文
                                    local res, msg, index = pcall(upprotFnc, data)
                                    if not res or not msg then
                                        log.error("数据流模版错误:", msg)
                                    else
                                        index = tonumber(index) or 1
                                        local pub_topic = (pub[index]:sub(-1, -1) == "+" and messageId) and
                                            pub[index]:sub(1, -2) .. messageId or pub[index]
                                        log.info("-----发布的主题:", pub_topic)
                                        if not mqttc:publish(pub_topic, res and msg or data, tonumber(pub[index + 1]) or qos,
                                                retain) then
                                            break
                                        end
                                    end
                                else
                                    local pub_topic = (pub[1]:sub(-1, -1) == "+" and messageId) and pub[1]:sub(1, -2) ..
                                        messageId or pub[1]
                                    log.info("-----发布的主题:", pub_topic)
                                    if not mqttc:publish(pub_topic, data, tonumber(pub[2]) or qos, retain) then
                                        break
                                    end
                                end
                                messageId = false
                                log.info('The client actively reports status information.')
                            else
                                -- log.info("匹配CID失败",data)
                            end
                        else
                                if  upprotFnc then -- 转换为用户自定义报文
                                local res, msg, index = pcall(upprotFnc, topic)
                                if not res or not msg then
                                    log.error("数据流模版错误:", msg)
                                else
                                    index = tonumber(index) or 1
                                    local pub_topic = (pub[index]:sub(-1, -1) == "+" and messageId) and
                                        pub[index]:sub(1, -2) .. messageId or pub[index]
                                    log.info("-----发布的主题:", pub_topic)
                                    if not mqttc:publish(pub_topic, res and msg or topic, tonumber(pub[index + 1]) or qos,
                                            retain) then
                                        break
                                    end
                                end
                            else
                                local pub_topic = (pub[1]:sub(-1, -1) == "+" and messageId) and pub[1]:sub(1, -2) ..
                                    messageId or pub[1]
                                log.info("-----发布的主题:", pub_topic)
                                if not mqttc:publish(pub_topic, topic, tonumber(pub[2]) or qos, retain) then
                                    break
                                end
                            end
                            messageId = false
                            log.info('The client actively reports status information.')
                        end
                        
                    elseif ret and topic == "mqttrecv" and recid==cid then
                        log.info("接收到了一条消息")
                        messageId = data:match(".+/rrpc/request/(%d+)")
                        log.info("MESSAGE", messageId)
                        log.info("RET2", ret, topic, data, payload)
                        -- 这里执行用户自定义的指令
                        if payload:sub(1, 5) == "rrpc," or payload:sub(1, 7) == "config," then
                            audio_uid=uid
                            audio_cid=cid
                            local res, msg = pcall(create.userapi, payload, pios)
                            if not res then
                                log.error("远程查询的API错误:", msg)
                            end
                            if dwprotFnc then -- 转换为用户自定义报文
                                res, msg = pcall(dwprotFnc, payload)
                                if not res then
                                    log.error("数据流模版错误:", msg)
                                end
                                res, msg = pcall(create.userapi, msg, pios)
                                if not res then
                                    log.error("远程查询的API错误:", msg)
                                end
                            end
                            if not mqttc:publish(pub[1], msg, tonumber(pub[2]) or qos, retain) then
                                break
                            end
                        elseif  dwprotFnc then -- 转换用户自定义报文
                            -- log.info("进到这里了3")
                            local res, msg = pcall(dwprotFnc, payload, data)
                            if not res or not msg then
                                log.error("数据流模版错误:", msg)
                            else
                                if prTopic == 1 then
                                    sys.publish("UART_SENT_RDY_" .. uid, uid,
                                        res and ("[+MSUB:" .. data .. "," .. #msg .. "," .. msg .. "]") or
                                        ("[+MSUB:" .. data .. "," .. #payload .. "," .. payload .. "]"))
                                else
                                    sys.publish("UART_SENT_RDY_" .. uid, uid, res and msg or payload)
                                end
                                -- sys.publish("UART_SENT_RDY_" .. uid, uid, res and msg or payload)
                            end
                        else -- 默认不转换
                            log.info("prTopic", prTopic, "UART_SENT_RDY_" .. uid)
                            if prTopic == 1 then
                                log.info("prTopic1", prTopic, "UART_SENT_RDY_" .. uid)
                                sys.publish("UART_SENT_RDY_" .. uid, uid,
                                    ("[+MSUB:" .. data .. "," .. #payload .. "," .. payload .. "]"))
                            else
                                log.info("prTopic2", prTopic, "UART_SENT_RDY_" .. uid)
                                sys.publish("UART_SENT_RDY_" .. uid, uid, payload)
                            end
                            -- sys.publish("UART_SENT_RDY_" .. uid, uid, payload)
                        end
                    elseif ret and topic == "mqttrecv" and recid~=cid then
                        log.info("另一个task发送过来的数据")
                    elseif ret == false then
                        log.warn("等待超时了")
                    elseif ret == true and topic=="disconnect" then
                        if data==cid then
                            log.warn("断开连接了")
                            break
                        else
                            log.info("另一个task断开")
                        end
                    else
                        log.warn('The MQTTServer connection is broken.')
                        break
                    end
                    -- elseif packet == 'timeout' then
                    --     -- sys.publish("AUTO_SAMPL_" .. uid)
                    --     log.debug('The client timeout actively reports status information.')
                    -- end
                end
            else
                log.info("订阅失败")
            end
        else
            log.info("连接服务器失败")
        end
        datalink[cid] = false
        mqttc:disconnect()
        log.info("断开连接了",cid)
        sys.wait((2 * idx) * 1000)
        if idx>9 then
            mobile.flymode(0,true)
            mobile.flymode(1,true)
            sys.wait(1000)
            mobile.flymode(0, false)
            mobile.flymode(1, false)
            idx=1
        else
            idx=idx + 1
        end
    end
end

local function aircloud_heart()
    local csq=mobile.csq()
    local eci=mobile.eci()
    local rsrp=mobile.rsrp()
    local scell=mobile.scell()
    local band
    if (scell.earfcn>= 0) and (scell.earfcn<=599) then
        band=1
    elseif (scell.earfcn>= 1200) and (scell.earfcn<=1949) then
        band=3
    elseif (scell.earfcn>= 2400) and (scell.earfcn<=2649) then
        band=5
    elseif (scell.earfcn>= 2750) and (scell.earfcn<=3449) then
        band=7
    elseif (scell.earfcn>= 3450) and (scell.earfcn<=3799) then
        band=8
    elseif (scell.earfcn>= 6150) and (scell.earfcn<=6449) then
        band=20
    elseif (scell.earfcn>= 37750) and (scell.earfcn<=38249) then
        band=38
    elseif (scell.earfcn>= 38250) and (scell.earfcn<=38649) then
        band=39
    elseif (scell.earfcn>= 38650) and (scell.earfcn<=39649) then
        band=40
    elseif (scell.earfcn>= 39650) and (scell.earfcn<=41589) then
        band=41
    end
    local heart={csq=csq,eci=eci,rsrp=rsrp,band=band}
    heart=json.encode(heart)
    return heart
end
local function aircloudTask(cid,pios,reg,upprot, dwprot, tasktype, prot, keepAlive,timeout,authkey,uid,ssl,qos)
    cid, keepAlive, timeout, uid = cid or 1, keepAlive or 300, timeout, uid
    qos = qos and qos or 0
    local autoReturn=true
    -- 如果当前时间点设置的默认网卡还没有连接成功，一直在这里循环等待
    while not socket.adapter(socket.dft()) do
        log.warn("tcp_client_main_task_func", "wait IP_READY", socket.dft())
        -- 在此处阻塞等待默认网卡连接成功的消息"IP_READY"
        -- 或者等待1秒超时退出阻塞等待状态;
        -- 注意：此处的1000毫秒超时不要修改的更长；
        -- 因为当使用exnetif.set_priority_order配置多个网卡连接外网的优先级时，会隐式的修改默认使用的网卡
        -- 当exnetif.set_priority_order的调用时序和此处的socket.adapter(socket.dft())判断时序有可能不匹配
        -- 此处的1秒，能够保证，即使时序不匹配，也能1秒钟退出阻塞状态，再去判断socket.adapter(socket.dft())
        sys.waitUntil("IP_READY", 1000)
    end
    local dwprotFnc = dwprot and dwprot[cid] and dwprot[cid] ~= "" and loadstring(dwprot[cid]:match("function(.+)end"))
    local upprotFnc = upprot and upprot[cid] and upprot[cid] ~= "" and loadstring(upprot[cid]:match("function(.+)end"))
    excloud.on(function(event, data)
        log.info("用户回调函数", event, json.encode(data))
    
        if event == "connect_result" then
            if data.success then
                datalink[cid] = true
                log.info("连接成功")
                if autoReturn then
                    if timeout>0 then
                        sys.publish("AUTO_SAMPL_"..uid)
                        sys.timerLoopStart(sys.publish, timeout * 1000, "AUTO_SAMPL_" .. uid)
                        autoReturn=false
                    end
                else
                    -- log.info("已经运行了")
                end
            else
                log.info("连接失败: " .. (data.error or "未知错误"))
            end
        elseif event == "auth_result" then
            if data.success then
                log.info("认证成功")
            else
                log.info("认证失败: " .. data.message)
            end
        elseif event == "message" then
            log.info("收到消息, 流水号: " .. data.header.sequence_num)
            -- 处理服务器下发的消息
            for _, tlv in ipairs(data.tlvs) do
                --控制命令  
                if tlv.field == excloud.FIELD_MEANINGS.CONTROL_COMMAND then
                    log.info("收到控制命令: " .. tostring(tlv.value),tlv.field)
                    
                    if  dwprotFnc then -- 转换用户自定义报文
                        log.info("收到透传数据: " .. tlv.value)
                        local res, msg = pcall(dwprotFnc, tlv.value,tlv.field)
                        if not res or not msg then
                            log.error("数据流模版错误:", msg)
                        end
                    else
                        log.info("收到数据: " .. tostring(tlv.value))
                    end
                    -- -- 处理控制命令并发送响应
                    -- local response_ok, err_msg = excloud.send({
                    --     {
                    --         field_meaning = excloud.FIELD_MEANINGS.CONTROL_RESPONSE,
                    --         data_type = excloud.DATA_TYPES.ASCII,
                    --         value = "OK"
                    --     }
                    -- }, false)
                    
                    -- if not response_ok then
                    --     log.info("发送控制响应失败: " .. err_msg)
                    -- end
                    --irtu命令
                elseif  tlv.field == excloud.FIELD_MEANINGS.IRTU_DOWN then
                    if tlv.value:sub(1, 5) == "rrpc," or tlv.value:sub(1, 7) == "config," then
                        audio_uid=uid
                        audio_cid=cid
                        local res, msg = pcall(create.userapi, tlv.value)
                            if not res then
                                log.error("远程查询的API错误:", msg)
                            end
                         local ok, err_msg = excloud.send({
                        {
                            field_meaning = excloud.FIELD_MEANINGS.IRTU_UP,
                            data_type = excloud.DATA_TYPES.ASCII,
                            value = msg     
                        }
                    }, false)
                    end
                else
                    --透传
                    if  dwprotFnc then -- 转换用户自定义报文
                        log.info("收到透传数据: " .. tlv.value,tlv.field)
                        local res, msg = pcall(dwprotFnc, tlv.value,tlv.field)
                        if not res or not msg then
                            log.error("数据流模版错误:", msg)
                        else
                            sys.publish("UART_SENT_RDY_" .. uid, uid, res and msg or tlv.value)
                        end
                    else
                        sys.publish("UART_SENT_RDY_"..uid,uid,tlv.value)
                    end
                end
                
            end
        elseif event == "disconnect" then
            datalink[cid] = false
            log.warn("与服务器断开连接")
        elseif event == "reconnect_failed" then
            log.info("重连失败，已尝试 " .. data.count .. " 次")
        elseif event == "send_result" then
            if data.success then
                log.info("发送成功，流水号: " .. data.sequence_num)
            else
                log.info("发送失败: " .. data.error_msg)
            end
        end
    end)

    sys.wait(1000)
    -- 配置excloud参数
    local ok, err_msg
    if prot=="tcp" then
        ok, err_msg = excloud.setup({
            device_type = 1,                 -- 设备类型: 4G
            use_getip = true, --使用getip服务
            auth_key = authkey, -- 鉴权密钥
            transport = "tcp",               -- 使用TCP传输
            auto_reconnect = true,           -- 自动重连
            reconnect_interval = 10,         -- 重连间隔(秒)
            max_reconnect = 5,               -- 最大重连次数
            timeout = 30,                    -- 超时时间(秒)
            mtn_log_enabled = true,  -- 启用运维日志
            mtn_log_blocks = 2,      -- 日志文件块数
            mtn_log_write_way = excloud.MTN_LOG_CACHE_WRITE  -- 缓存写入方式
        })
    elseif prot=="mqtt" then
        ok, err_msg = excloud.setup({
            device_type = 1,                 -- 设备类型: 4G
            use_getip = true, --使用getip服务
            auth_key = authkey, -- 鉴权密钥
            transport = "mqtt",               -- 使用TCP传输
            auto_reconnect = true,           -- 自动重连
            reconnect_interval = 10,         -- 重连间隔(秒)
            max_reconnect = 5,               -- 最大重连次数
            timeout = 30,                    -- 超时时间(秒)
            qos=qos,              --mqtt qos
            mtn_log_enabled = true,  -- 启用运维日志
            mtn_log_blocks = 2,      -- 日志文件块数
            mtn_log_write_way = excloud.MTN_LOG_CACHE_WRITE  -- 缓存写入方式
        })
    end

    if not ok then
        log.info("初始化失败: " .. err_msg)
        return
    end
    log.info("excloud初始化成功")
    -- 开启excloud服务
    local ok, err_msg = excloud.open()
    if not ok then
        log.info("开启excloud服务失败: " .. err_msg)
        return
    end

    log.info("excloud服务已开启")
    -- 在主循环中定期上报数据
    local outputSocket = {}
    local subMessage = function(data,data2)
        if data then
            if data~="mqttrecv" and data~="disconnect"then
                if data:match("GPSCID_") then
                    -- log.info("是GPS发过来的消息")
                    if data== "GPSCID_"..cid then
                        -- log.info("匹配CID成功",cid)
                        table.insert(outputSocket, data2)
                        sys.publish("SEND_DATA")
                    else
                        -- log.info("匹配CID失败",data)
                    end
                elseif data:match("audioresult_") then
                    if data== "audioresult_"..cid then
                        -- log.info("匹配CID成功",cid)
                        table.insert(outputSocket, data2)
                        sys.publish("SEND_DATA")
                    else
                        -- log.info("匹配CID失败",data)
                    end
                else
                table.insert(outputSocket, data)
                sys.publish("SEND_DATA")
                end
            end
        end
    end
    sys.subscribe("NET_SENT_RDY_" .. uid, subMessage)
    while true do
        -- 每30秒上报一次数据
        -- sys.wait(30000)
        local ret=sys.waitUntil("SEND_DATA",(keepAlive*1000))
        if not ret then
            local ok, err_msg = excloud.send({
                {
                    field_meaning = excloud.FIELD_MEANINGS.RANDOM_DATA,
                    data_type = excloud.DATA_TYPES.ASCII,
                    value = aircloud_heart()
                }
            }, false)                   -- 不需要服务器回复
    
        else
            while #outputSocket>0 do
                local data=table.remove(outputSocket,1)
                log.info("RET",ret,data)
                    if  upprotFnc then -- 转换为用户自定义报文
                        local res, msg = pcall(upprotFnc, data)
                        if not res or not msg then
                            log.error("数据流模版错误:", msg)
                        else
                            local ok, err_msg = excloud.send({
                                {
                                    field_meaning = excloud.FIELD_MEANINGS.RANDOM_DATA,
                                    data_type = excloud.DATA_TYPES.ASCII,
                                    value = (res and msg or data)    
                                }
                            }, false)                   -- 不需要服务器回复
                            
                        end
                    else -- 默认不转换
                        local ok, err_msg = excloud.send({
                            {
                                field_meaning = excloud.FIELD_MEANINGS.RANDOM_DATA,
                                data_type = excloud.DATA_TYPES.ASCII,
                                value = data     
                            }
                        }, false)                   -- 不需要服务器回复
                    end
                
                if not ok then
                    log.info("发送数据失败: " .. err_msg )
                else
                    log.info("数据发送成功")
                end
            end
        end
    end
end

---------------------------------------------------------- 参数配置,任务转发，线程守护主进程----------------------------------------------------------
function connect(pios, conf, reg, upprot, dwprot)
    local flyTag = false
    -- 如果当前时间点设置的默认网卡还没有连接成功，一直在这里循环等待
    while not socket.adapter(socket.dft()) do
        -- log.warn("tcp_client_main_task_func", "wait IP_READY", socket.dft())
        -- 在此处阻塞等待默认网卡连接成功的消息"IP_READY"
        -- 或者等待1秒超时退出阻塞等待状态;
        -- 注意：此处的1000毫秒超时不要修改的更长；
        -- 因为当使用exnetif.set_priority_order配置多个网卡连接外网的优先级时，会隐式的修改默认使用的网卡
        -- 当exnetif.set_priority_order的调用时序和此处的socket.adapter(socket.dft())判断时序有可能不匹配
        -- 此处的1秒，能够保证，即使时序不匹配，也能1秒钟退出阻塞状态，再去判断socket.adapter(socket.dft())
        sys.waitUntil("IP_READY", 1000)
    end
    sys.waitUntil("DTU_PARAM_READY", 120000)
    -- 自动创建透传任务并填入参数
    for k, v in pairs(conf or {}) do
        if v[1] and (v[1]:upper() == "SOCKET") then
            log.warn("----------------------- TCP/UDP is start! --------------------------------------")
            --log.info("webProtect", webProtect, protectContent[1])
            local taskName = "DTU_" .. tostring(k)
            sys.taskInitEx(tcpTask, taskName, netCB, taskName, k, pios, reg,upprot, dwprot,
                unpack(v))
        elseif v[1] and v[1]:upper() == "MQTT" then
            local taskName = "DTU_" .. tostring(k)
            log.warn("----------------------- MQTT is start! --------------------------------------")
            sys.taskInitEx(mqttTask, taskName,netCB,k, pios, reg,upprot, dwprot, unpack(v, 2))
        
        elseif v[1] and v[1]:upper() == "AIRCLOUD" then
            local taskName = "DTU_" .. tostring(k)
            log.warn("----------------------- Aircloud is start! --------------------------------------")
            -- log.info("k",k,unpack(v))
            sys.taskInitEx(aircloudTask,taskName,netCB,k, pios, reg,upprot, dwprot,unpack(v))
        end
    end
end


sys.subscribe("IP_READY", function()
    log.info("---------------------- 网络注册已成功 ----------------------")
end)
sys.subscribe("IP_LOSE", function(adapter)
    log.info("---------------------- 网络注册失败 ----------------------")
    log.info("mobile", "IP_LOSE", (adapter or -1) == socket.LWIP_GP)
end)

function create.start()
    dtu = default.get()
    ---------------------------------------------------------- 参数配置,任务转发，线程守护主进程----------------------------------------------------------
    sys.taskInit(connect, default.pios, dtu.conf, dtu.reg,dtu.upprot, dtu.dwprot)
end

return create
