--[[
@module  auxServer
@summary 测试服务器模块：实现JT808协议通信、设备注册鉴权、数据上报
@version 1.0
@author  Auto
@usage
本模块实现以下功能：
1. 服务器连接管理：DNS解析、TCP连接、断线重连
2. 设备注册：0x0100注册请求，0x8100注册应答解析
3. 设备鉴权：0x0102鉴权请求，0x8001通用应答解析
4. 数据上报：0x0200位置信息上报
5. 指令处理：0x8202跟踪参数设置、0x8900透传数据
6. OTA升级：集成libfota固件升级
7. 飞行模式：连接失败3次后进入飞行模式
]]

local moduleName = "测试服务器"
local taskName = "auxTask"
local libfota = require "libfota"
local auxServer = {}

-- ==================== 全局变量 ====================

-- 设备ID（从IMEI提取的12位数字）
local simID = nil

-- 连接状态
local connectOk = false

-- 数据发送相关标志
local isWaitMsg, isResponseOK, isResponseNeedCheck, connectOKFlag, waitAck

-- 消息流水号和消息ID
local lastTxMsgID, lastTxMsgSn, lastRxMsgID, lastRxData, localMsgID

-- 数据队列
local responseQueue, dataQueue

local logSwitch = true

local logSwitch = true

local function logF(...)
    if logSwitch then
        log.info(moduleName, ...)
    end
end

-- ==================== 网络回调 ====================

--[[
处理未识别的网络消息
接收libnet模块传递的网络事件消息

@param msg 消息数组，包含事件类型和参数
@local
]]
local function netCB(msg)
    logF("unprocessed message", msg[1], msg[2], msg[3], msg[4])
end

-- ==================== 导出函数 ====================

--[[
客户端定位数据发送
将定位数据添加到发送队列，如果连接正常则触发发送

功能：
1. 检查时间是否已校准（年份>=2024）
2. 限制队列最大长度为200，超限则删除最旧数据
3. data为nil时自动获取定位数据
4. 连接正常时触发socket发送事件

@api auxServer.dataSend(data)
@any data 可选，要发送的数据（zbuff类型），nil时自动获取定位数据
@return boolean, number 成功返回true和0，失败返回false和0
@usage
-- 自动获取定位数据并发送
auxServer.dataSend()

-- 发送自定义数据
local buf = zbuff.create(200)
auxServer.dataSend(buf)
]]
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

--[[
获取客户端连接状态

@api auxServer.isConnected()
@return boolean true=已连接，false=未连接
@usage
if auxServer.isConnected() then
    log.info("服务器已连接")
end
]]
function auxServer.isConnected()
    return connectOKFlag
end

-- ==================== 服务器应答解析 ====================

--[[
客户端注册应答解析
解析服务器返回的0x8100注册应报文

功能：
1. 验证消息流水号是否匹配
2. 验证注册结果（procResult=0表示成功）
3. 保存鉴权码到fskv

@param inData 应答消息体
@local
]]
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

--[[
客户端通用应答解析
解析服务器返回的0x8001通用应报文

功能：
1. 验证消息流水号和消息ID是否匹配
2. 验证处理结果（procResult=0或4表示成功）
3. 设置isResponseOK标志

@param inData 应答消息体
@local
]]
local function monitorRxResponse(inData)
    local lastMsgSn, lastMsgID, procResult = jt808.analyzeMonitorResopnse(inData)
    if isResponseNeedCheck then
        logF("rx normal response", string.format("%04x", lastTxMsgID), string.format("%04x", lastMsgID), lastTxMsgSn, lastMsgSn, procResult)
        if (lastTxMsgID == lastMsgID) and (lastTxMsgSn == lastMsgSn) and ((procResult == 0) or (procResult == 4)) then
            logF("rx response ok")
            isResponseNeedCheck = false
            isResponseOK = true
        else
            isResponseOK = false
        end
    end
end

--[[
跟踪参数设置响应解析（0x8202）
解析服务器下发的跟踪参数设置指令

功能：
1. 解析上报间隔和超时时间
2. 调用common.setfastUpload设置快速上传模式
3. 发送0x0001通用应答

参数格式：
- interval: 上报间隔（分钟）
- timeout: 超时时间（分钟）

@param inData 消息体
@param msgSn 消息流水号
@local
]]
local function monitorTrackIngResponse(inData, msgSn)
    logF("track data", inData:toHex(), msgSn)
    if #inData ~= 6 then
        return
    end
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

--[[
透传数据响应解析（0x8900）
解析服务器下发的透传数据（如联系人列表）

功能：
1. 检查数据标识（0xF1表示联系人列表）
2. 解析JSON格式的联系人数据
3. 保存联系人列表到fskv
4. 发送0x0900透传应答

数据格式：
- Flag(1B): 0xF1表示联系人列表
- Data: JSON格式的联系人列表

@param inData 消息体
@param msgSn 消息流水号
@local
]]
local function monitorDlTrans(inData, msgSn)
    local result, ret, data = true, nil, nil
    if #inData > 0 then
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

-- ==================== 命令分发表 ====================

--[[
注册命令解析函数表
将消息ID映射到对应的处理函数

消息ID映射：
- 0x8001: monitorRxResponse（通用应答）
- 0x8100: monitorRxReg（注册应答）
- 0x8202: monitorTrackIngResponse（跟踪参数设置）
- 0x8900: monitorDlTrans（透传数据）
]]
local monitorRxFun = {
    [0x8001] = monitorRxResponse,
    [0x8100] = monitorRxReg,
    [0x8202] = monitorTrackIngResponse,
    [0x8900] = monitorDlTrans
}

--[[
命令消息分发
根据消息ID调用对应的解析函数

功能：
1. 遍历消息队列
2. 根据msgID查找对应的处理函数
3. 调用处理函数解析消息体

@param param 消息队列数组，每个元素包含msgID、msgSn、body
@local
]]
local function msgDispatch(param)
    logF("dispatch", param)
    for index, msg in pairs(param) do
        logF("msg", msg.msgID, msg.body:toHex())
        if monitorRxFun[msg.msgID] then
            monitorRxFun[msg.msgID](msg.body, msg.msgSn)
        end
    end
end

--[[
重启设备回调函数
OTA升级成功后重启设备

功能：
1. 检查升级结果（ret=0表示成功）
2. 调用pm.reboot重启设备

@param ret 升级结果，0=成功，其他=失败
@local
]]
local function reBootDevice(ret)
    if ret == 0 then
        pm.reboot()
    end
end

-- ==================== 服务器任务主循环 ====================

--[[
测试服务器任务主循环
管理与服务器的通信流程，包含5个状态机

状态机：
1. WAIT_NET_READY: 等待网络就绪
2. REQ_SERVER: 请求服务器地址
3. REG_DEVICE: 设备注册
4. AUTH_DEVICE: 设备鉴权
5. MSG_LISTEN: 监听服务器消息
6. FLY_MODE: 飞行模式（连接失败3次后）

功能：
- DNS解析服务器地址
- 设备注册和鉴权
- 位置数据上报
- 服务器指令处理
- 断线重连
- OTA升级检查
- 飞行模式保护

@param d1Name 任务名称（用于消息传递）
@local
]]
local function auxServerTask(d1Name)
    -- ==================== 状态机初始化 ====================

    local result, data, queue, rxBuff, param, param2, ip, port, succ, netc, authCode, pTxBuf
    local firstWaitNetReady = true    -- 首次等待网络标志
    local nowStatus = "WAIT_NET_READY"  -- 当前状态
    local retryTimes = 0              -- 重试次数
    local recvTimeout = 0              -- 接收超时
    localMsgID = 0                    -- 本地消息流水号
    dataQueue = {}                     -- 数据发送队列
    rxBuff = zbuff.create(1024)       -- 接收缓冲区

    -- ==================== 状态机主循环 ====================

    while true do
        ::CONTINUE::

        -- ==================== 状态1: 等待网络就绪 ====================
        if nowStatus == "WAIT_NET_READY" then
            responseQueue = {}
            lastRxData = ""
            sys.cleanMsg(d1Name)
            connectOKFlag = false
            if not firstWaitNetReady then
                retryTimes = retryTimes + 1
                libnet.close(d1Name, 5000, netc)
                socket.release(netc)
                if retryTimes > 3 then
                    nowStatus = "FLY_MODE"
                    goto CONTINUE
                end
                math.randomseed(os.time())
                sys.wait(math.random(10, 20) * 1000)
            end
            while not netWork.isReady() do
                sys.wait(1000)
            end
            if firstWaitNetReady then
                socket.sntp()
                firstWaitNetReady = false
                libfota.request(reBootDevice)
                sys.timerLoopStart(libfota.request, 3600000, reBootDevice)
            end
            nowStatus = "REQ_SERVER"
            goto CONTINUE
        end

        -- ==================== 状态2: 请求服务器地址 ====================
        if nowStatus == "REQ_SERVER" then
            sys.wait(3000)
            netc = socket.create(nil, d1Name)
            socket.config(netc, nil, false, nil, 300, 10, 3)
            local code, headers, body = http.request("GET", string.format("https://gps.openluat.com/iot/getip?clientid=%s&p=%s", mobile.imei():sub(3, 14), _G.PRODUCT_VER)).wait()
            log.info("连接ip 请求结果", code, headers, body)
            if (code == 200 or code == 206) and body then
                local data, result = json.decode(body)
                if result == 1 and type(data) == "table" and data.msg == "ok" then
                    if data.ipv4 and data.tcp then
                        log.info("使用IPV4 TCP方式连接服务器")
                        ip = data.ipv4
                        port = data.tcp
                    else
                        log.info("服务器没有返回IPV4地址，使用IPV4 TCP方式连接服务器")
                        nowStatus = "WAIT_NET_READY"
                        goto CONTINUE
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

        -- ==================== 状态3: 设备注册 ====================
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
            succ, param = socket.rx(netc, rxBuff)
            if not succ then
                logF("服务器断开了")
                nowStatus = "WAIT_NET_READY"
                goto CONTINUE
            end
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

        -- ==================== 状态4: 设备鉴权 ====================
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
            succ, param = socket.rx(netc, rxBuff)
            if not succ then
                logF("数据读取出现异常 4", succ, param, ip, port)
                nowStatus = "WAIT_NET_READY"
                goto CONTINUE
            end
            if rxBuff:used() > 0 then
                data = rxBuff:query()
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

        -- ==================== 状态5: 监听服务器消息 ====================
        if nowStatus == "MSG_LISTEN" then
            connectOKFlag = true
            logF("开始监听")
            while true do
                waitAck = false
                while #responseQueue > 0 do
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
                if rxBuff:used() > 0 then
                    logF("socket", "收到服务器数据，长度", rxBuff:used())
                    data = rxBuff:query()
                    rxBuff:del()
                    logF("rxData", data:toHex())
                    lastRxData, queue = jt808.rxAnalyze(lastRxData .. data)
                    msgDispatch(queue)
                end
            end
            goto CONTINUE
        end

        -- ==================== 状态6: 飞行模式 ====================
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

-- ==================== 启动服务器任务 ====================

--[[
启动测试服务器任务
使用sys.taskInitEx创建任务，绑定网络回调

说明：
- taskName: 任务名称，用于消息传递
- netCB: 网络回调函数，处理未识别的网络消息
]]
sys.taskInitEx(auxServerTask, taskName, netCB, taskName)

return auxServer
