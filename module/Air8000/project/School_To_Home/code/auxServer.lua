local moduleName = "建栋服务器"
local taskName = "auxTask"
local libfota = require "libfota"
local auxServer = {}
local simID = nil
local connectOk = false
local isWaitMsg, isResponseOK, isResponseNeedCheck, connectOKFlag, waitAck
local lastTxMsgID, lastTxMsgSn, lastRxMsgID, lastRxData, localMsgID
local responseQueue, dataQueue

local logSwitch = true

local function logF(...)
    if logSwitch then
        log.info(moduleName, ...)
    end
end

-- 处理未识别的网络消息
local function netCB(msg)
    logF("unprocessed message", msg[1], msg[2], msg[3], msg[4])
end

-- 客户端定位数据发送
function auxServer.dataSend(data)
    local tTime = os.date("!*t", os.time())
    if tTime.year < 2024 then
        logF("时间未校准，放弃本次数据上传")
        return false, 0
    end
    if #dataQueue > 200 then
        local item = table.remove(dataQueue, 1)
        item:free()
    end
    if not data then
        local item = zbuff.create(200)
        item:copy(nil, common.monitorRecord())
        table.insert(dataQueue, item)
    else
        table.insert(dataQueue, data)
    end
    if isWaitMsg and connectOKFlag then
        sys_send(taskName, socket.EVENT, 0)
    end
    return true, 0
end

-- 客户端连接状态
function auxServer.isConnected()
    return connectOKFlag
end

-- 客户端注册应答解析
local function monitorRxReg(inData)
    logF(inData:toHex())
    local lastMsgSn, procResult, authCode = jt808.analyzeRegResopnse(inData)
    logF("rx reg response", lastTxMsgSn, lastMsgSn, procResult, authCode:toHex())
    if (lastMsgSn == lastTxMsgSn) and (procResult == 0) and (authCode ~= nil) then
        fskv.set("authCode2", authCode)
        isResponseOK = true
    else
        isResponseOK = false
    end
    logF("isresponseok", isResponseOK)
end

-- 客户端通用应答解析
local function monitorRxResponse(inData)
    local lastMsgSn, lastMsgID, procResult = jt808.analyzeMonitorResopnse(inData)
    if isResponseNeedCheck then
        logF("rx normal response", string.format("%04x", lastTxMsgID), string.format("%04x", lastMsgID), lastTxMsgSn, lastMsgSn, procResult)
        if (lastTxMsgID == lastMsgID) and (lastMsgSn == lastTxMsgSn) and ((procResult == 0) or (procResult == 4)) then
            logF("rx response ok")
            isResponseNeedCheck = false
            isResponseOK = true
        else
            isResponseOK = false
        end
    end
end

local function monitorTrackIngResponse(inData, msgSn)
    logF("track data", inData:toHex(), msgSn)
    if #inData ~= 6 then
        return
    end
    -- local interval, timeout = tonumber(inData:sub(1, 2), 2), tonumber(inData:sub(3), 2)
    local _, interval, timeout = pack.unpack(inData, ">hI")
    logF("interval", interval, timeout)
    if not interval or not timeout or interval <= 0 and timeout < 0 then
        return
    end
    local pTxBuf = ""
    localMsgID = (localMsgID + 1) % 65536
    pTxBuf = jt808.jt808Head(0x0001, localMsgID, simID, pTxBuf)
    table.insert(responseQueue, pTxBuf)
    common.setfastUpload(interval, timeout)
end

local function monitorDlTrans(inData, msgSn)
    local result, ret, data = true, nil, nil
    if #inData > 0 then
        --  解析indata从第2个位置开始的json数据
        local flag = string.sub(inData, 1, 1)
        if string.byte(flag) == 0xF1 then
            local data, ret = json.decode(inData:sub(2))
            log.info("data", result)
            if ret == 1 then
                fskv.set("phoneList", data)
                for k, v in pairs(data) do
                    if v and v.name and v.num then
                        logF("联系人列表", v, string.fromHex(v.name), v.num)
                    end
                end
            else
                result = false 
            end
        else
            result = false
        end
    else
        result = false
    end

    localMsgID = (localMsgID + 1) % 65536
    local pTxBuf = jt808.makeTransResponseBody(result and "OK#" or "ERROR#")
    pTxBuf = jt808.jt808Head(0x0900, localMsgID, simID, pTxBuf)
    table.insert(responseQueue, pTxBuf)
end

-- 注册命令解析函数
local monitorRxFun = {
    [0x8001] = monitorRxResponse,
    [0x8100] = monitorRxReg,
    [0x8202] = monitorTrackIngResponse,
    [0x8900] = monitorDlTrans
}

-- 命令消息分发
local function msgDispatch(param)
    logF("dispatch", param)
    for index, msg in pairs(param) do
        logF("msg", msg.msgID, msg.body:toHex())
        if monitorRxFun[msg.msgID] then
            monitorRxFun[msg.msgID](msg.body, msg.msgSn)
        end
    end
end

-- 重启设备
local function reBootDevice(ret)
    if ret == 0 then
        pm.reboot()
    end
end

local function auxServerTask(d1Name)
    local result, data, queue, rxBuff, param, param2, ip, port, succ, netc, authCode, pTxBuf
    local firstWaitNetReady = true
    local nowStatus = "WAIT_NET_READY"
    local retryTimes = 0
    local recvTimeout = 0
    local ipv6Valid = false
    localMsgID = 0
    dataQueue = {}
    rxBuff = zbuff.create(1024)
    while true do
        ::CONTINUE::
        if nowStatus == "WAIT_NET_READY" then
            responseQueue = {}
            lastRxData = ""
            sysplus.cleanMsg(d1Name)
            connectOKFlag = false
            if not firstWaitNetReady then
                retryTimes = retryTimes + 1
                libnet.close(d1Name, 5000, netc)
                socket.release(netc)
                if retryTimes > 3 then -- 重试3次，进入FLY_MODE
                    nowStatus = "FLY_MODE"
                    goto CONTINUE
                end
                math.randomseed(os.time()) -- 设置随机数种子
                sys.wait(math.random(10, 20) * 1000)
            end
            while not netWork.isReady() do -- 等待网络就绪
                sys.wait(1000)
            end
            if firstWaitNetReady then -- 第一次或者进出飞行模式后等待网络就绪， 触发下远程升级
                socket.sntp()
                firstWaitNetReady = false
                libfota.request(reBootDevice)
                sys.timerLoopStart(libfota.request, 3600000, reBootDevice)
            end
            nowStatus = "REQ_SERVER"
            goto CONTINUE
        end

        if nowStatus == "REQ_SERVER" then
            sys.wait(3000)
            local _0, _1, _2, ipv6 = socket.localIP()
            if ipv6 and #ipv6 > 0 and ipv6:sub(1, 2) ~= "FE" then
                ipv6Valid = true
            else
                ipv6Valid = false 
            end
            netc = socket.create(nil, d1Name)
            if _G.IPV6_UDP_VER and ipv6Valid then
                socket.config(netc, 12398, true) 
            else
                socket.config(netc, nil, false)
            end
            local code, headers, body = http.request("GET", string.format("https://gps.openluat.com/iot/getip?clientid=%s&p=%s", mobile.imei():sub(3, 14), _G.PRODUCT_VER)).wait()
            log.info("连接ip 请求结果", code, headers, body)
            if (code == 200 or code == 206) and body then
                local data, result = json.decode(body)
                if result == 1 and type(data) == "table" and data.msg == "ok" then
                    if _G.IPV6_UDP_VER then
                        if ipv6Valid and data.ipv6 and data.udp then
                            log.info("获取到IPV6地址，且服务器返回了IPV6地址，使用IPV6 UDP方式连接服务器")
                            ip = data.ipv6
                            port = data.udp
                        else
                            if not ipv6Valid then
                                log.info("设备没有分配到IPV6地址，使用IPV4 TCP方式连接服务器")
                            end

                            if not data.ipv6 or not data.udp then
                                log.info("服务器没有返回IPV6地址或UDP端口，使用IPV4 TCP方式连接服务器")
                            end

                            if data.ipv4 and data.tcp then
                                log.info("使用IPV4 TCP方式连接服务器")
                                ip = data.ipv4
                                port = data.tcp
                            else
                                nowStatus = "WAIT_NET_READY"
                                goto CONTINUE
                            end
                        end
                    else
                        if data.ipv4 and data.tcp then
                            log.info("使用IPV4 TCP方式连接服务器")
                            ip = data.ipv4
                            port = data.tcp
                        else
                            log.info("服务器没有返回IPV4地址，使用IPV4 TCP方式连接服务器")
                            nowStatus = "WAIT_NET_READY"
                            goto CONTINUE
                        end
                    end
                else
                    nowStatus = "WAIT_NET_READY"
                    goto CONTINUE
                end
            else
                nowStatus = "WAIT_NET_READY"
                goto CONTINUE
            end

            simID = mobile.imei():sub(3, 14)
            simID = api.StrToBin(simID)
            result = libnet.connect(d1Name, 30000, netc, ip, port)
            if not result then
                nowStatus = "WAIT_NET_READY"
            else
                nowStatus = "REG_DEVICE"
            end
            goto CONTINUE
        end
        if nowStatus == "REG_DEVICE" then
            authCode = fskv.get("authCode2")
            if authCode and #authCode > 0 then
                nowStatus = "AUTH_DEVICE"
                goto CONTINUE
            end
            localMsgID = (localMsgID + 1) % 65536
            lastTxMsgSn = localMsgID
            pTxBuf = jt808.makeRegMsg(0, 0, "", string.fromHex(string.rep("0", 36) .. _G.PRODUCT_VER), api.StrToBin(mobile.imei():sub(1, 14)), 0, string.char(0x00))
            pTxBuf = jt808.jt808Head(0x0100, localMsgID, simID, pTxBuf)
            result, param = libnet.tx(d1Name, 15000, netc, pTxBuf)
            if not result then
                logF("注册发送异常")
                nowStatus = "WAIT_NET_READY"
                goto CONTINUE
            end
            logF("注册发送成功")
            result, param = libnet.wait(d1Name, 30000, netc)
            if not result then
                logF("注册数据等待异常", result, param)
                nowStatus = "WAIT_NET_READY"
                goto CONTINUE
            end
            if not ipv6Valid and IPV6_UDP_VER then
                if not param then
                    logF("注册数据等待超时", result, param)
                    nowStatus = "WAIT_NET_READY"
                    goto CONTINUE
                end
            end
            succ, param = socket.rx(netc, rxBuff)
            if not succ then
                logF("服务器断开了")
                nowStatus = "WAIT_NET_READY"
                goto CONTINUE
            end
            -- 如果服务器有下发数据, used()就必然大于0, 进行处理
            if rxBuff:used() > 0 then
                data = rxBuff:query()
                rxBuff:del()
                isResponseOK = false
                lastRxData, queue = jt808.rxAnalyze(lastRxData .. data)
                msgDispatch(queue)
                if not isResponseOK then
                    nowStatus = "WAIT_NET_READY"
                    goto CONTINUE
                end
                nowStatus = "AUTH_DEVICE"
                logF("注册成功")
            end
            goto CONTINUE
        end
        if nowStatus == "AUTH_DEVICE" then
            if mreport then
                mreport.send()
            end
            localMsgID = (localMsgID + 1) % 65536
            lastTxMsgSn = localMsgID
            pTxBuf = jt808.authPackage(lastTxMsgSn, simID, fskv.get("authCode2"))
            lastTxMsgID = 0x0102
            result, param = libnet.tx(d1Name, 15000, netc, pTxBuf)
            if not result then
                logF("鉴权发送失败")
                nowStatus = "WAIT_NET_READY"
                goto CONTINUE
            end
            logF("鉴权发送成功")
            result, param = libnet.wait(d1Name, 30000, netc)
            if not result then
                logF("鉴权数据等待异常", result, param)
                nowStatus = "WAIT_NET_READY"
                goto CONTINUE
            end
            if not ipv6Valid and IPV6_UDP_VER then
                if not param then
                    logF("鉴权 超时未收到响应报文")
                    nowStatus = "WAIT_NET_READY"
                    goto CONTINUE
                end
            end
            succ, param = socket.rx(netc, rxBuff)
            if not succ then
                logF("数据读取出现异常 4", succ, param, ip, port)
                nowStatus = "WAIT_NET_READY"
                goto CONTINUE
            end
            if rxBuff:used() > 0 then
                data = rxBuff:query() -- 获取数据
                rxBuff:del()
                logF("data", data:toHex())
                isResponseOK = false
                isResponseNeedCheck = true
                lastRxData, queue = jt808.rxAnalyze(lastRxData .. data)
                msgDispatch(queue)
                if not isResponseOK then
                    logF("鉴权失败")
                    nowStatus = "WAIT_NET_READY"
                    goto CONTINUE
                end
                logF("鉴权成功")
                nowStatus = "MSG_LISTEN"
                retryTimes = 0
            end
            goto CONTINUE
        end
        if nowStatus == "MSG_LISTEN" then
            connectOKFlag = true
            logF("开始监听")
            while true do
                waitAck = false
                while #responseQueue > 0 do
                    -- 应答区有数据
                    pTxBuf = responseQueue[1]
                    result, param = libnet.tx(d1Name, 15000, netc, pTxBuf)
                    if not result then
                        nowStatus = "WAIT_NET_READY"
                        goto CONTINUE
                    end
                    table.remove(responseQueue, 1)
                    logF("response packet", api.BinToHex(pTxBuf, " "))
                end
                if #dataQueue > 0 then
                    if mreport then
                        mreport.send()
                    end
                    local item = dataQueue[1]
                    localMsgID = (localMsgID + 1) % 65536
                    lastTxMsgSn = localMsgID
                    pTxBuf = jt808.positionPackage(lastTxMsgSn, simID, item:query())
                    lastTxMsgID = 0x0200
                    logF("data packet", #pTxBuf, api.BinToHex(pTxBuf, " "))
                    result, param = libnet.tx(d1Name, 15000, netc, pTxBuf)
                    if not result then
                        nowStatus = "WAIT_NET_READY"
                        goto CONTINUE
                    end
                    item:free()
                    table.remove(dataQueue, 1)
                    waitAck = true
                end
                isWaitMsg = true
                if waitAck then
                    result, param = libnet.wait(d1Name, 60000, netc)
                else
                    result, param = libnet.wait(d1Name, 300000, netc)
                end
                isWaitMsg = false
                logF("wait", result, param, param2)
                if not result then
                    logF("服务器断开了 5", result, param)
                    nowStatus = "WAIT_NET_READY"
                    goto CONTINUE
                end
                succ, param = socket.rx(netc, rxBuff)
                if not succ then
                    logF("服务器断开了 6", succ, param, ip, port)
                    nowStatus = "WAIT_NET_READY"
                    goto CONTINUE
                end
                -- 如果服务器有下发数据, used()就必然大于0, 进行处理
                if rxBuff:used() > 0 then
                    logF("socket", "收到服务器数据，长度", rxBuff:used())
                    data = rxBuff:query()
                    rxBuff:del()
                    logF("rxData", data:toHex())
                    lastRxData, queue = jt808.rxAnalyze(lastRxData .. data)
                    msgDispatch(queue)
                end
                -- 循环尾部, 继续下一轮循环
            end
            goto CONTINUE
        end
        if nowStatus == "FLY_MODE" then
            firstWaitNetReady = true
            netWork.setFlyMode(true)
            sys.waitUntil("EXIT_FLYMODE", 10 * 60 * 1000)
            netWork.setFlyMode(false)
            nowStatus = "WAIT_NET_READY"
            goto CONTINUE
        end
    end
end
sysplus.taskInitEx(auxServerTask, taskName, netCB, taskName)
return auxServer
