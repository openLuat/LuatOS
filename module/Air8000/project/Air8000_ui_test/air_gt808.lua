local moduleName = "air_jt808"
local air_jt808 = {}
local logSwitch = false
local function logF(...)
    if logSwitch then
        log.info(moduleName, ...)
    end
end
-- 发送数据转义
-- inData string
-- 输出string
local function msgEncode(inData)
    local oldString = string.char(0x7d)
    local newString = string.char(0x7d) .. string.char(0x01)
    inData = string.gsub(inData, oldString, newString)
    oldString = string.char(0x7e)
    newString = string.char(0x7d) .. string.char(0x02)
    inData = string.gsub(inData, oldString, newString)
    return oldString .. inData .. oldString
end

-- 接收数据转义，输入数据不能包含0x7e
-- inData string型
-- 输出string
local function msgDecode(inData)
    local oldString = string.char(0x7d) .. string.char(0x02)
    local newString = string.char(0x7e)
    inData = string.gsub(inData, oldString, newString)
    oldString = string.char(0x7d) .. string.char(0x01)
    newString = string.char(0x7d)
    return string.gsub(inData, oldString, newString)
end

-- 接收包头解析
-- inData string型
-- 输出
-- msgID 平台发送包的ID uint16_t
-- msgSn 平台发送包的SN uint16_t
-- simID 设备ID string
-- msgBuf 数据体 string
local function analyzeHead(inData)

    local msgID, msgSn, simID, msgLen, Len, i, msgBuf
    if type(inData) ~= "string" then
        return nil
    end
    Len = #inData

    msgID = api.BigBinToNum(string.sub(inData, 1, 2), 2)
    msgLen = api.BigBinToNum(string.sub(inData, 3, 4), 2)

    if msgLen ~= (Len - 12) then
        log.error(moduleName, "协议头长度不正确", msgLen, Len - 12)
        -- if msgLen ~= (Len - 13) then
        -- log.error(moduleName,"协议头长度不正确", msgLen, Len - 13)
        return nil
    end
    simID = string.sub(inData, 5, 10)
    msgSn = api.BigBinToNum(string.sub(inData, 11, 12), 2)
    msgBuf = string.sub(inData, 13, #inData)
    -- simID = string.sub(inData, 5, 11)
    -- msgSn = api.BigBinToNum(string.sub(inData, 12, 13), 2)
    -- msgBuf = string.sub(inData, 14, #inData)

    return msgID, msgSn, simID, msgBuf
end

-- 接收数据解析
-- inData string型
-- 输出
-- packet 有效的接收包
-- lastData 剩余数据
local function analyzePacket(inData)
    local packet, lastData
    local matchByte = string.char(0x7e)
    local Pos = string.find(inData, matchByte)

    if Pos == nil then
        -- 找不到开始标识符
        return nil, nil
    end

    inData = string.sub(inData, Pos + 1, #inData)
    Pos = string.find(inData, matchByte)

    if Pos == nil then
        -- 找不到结束标识符
        return nil, inData
    end

    packet = string.sub(inData, 1, Pos - 1)
    lastData = string.sub(inData, Pos, #inData)
    return packet, lastData
end

-- 客户端接收解析
function air_jt808.rxAnalyze(lastRxData)
    local lastRxMsgSn = 0
    local queue = {}
    local result, msgID, msgSn, msgBody, rxSimID, inData, packet, check
    logF("rxdata", #lastRxData, api.BinToHex(lastRxData, " "))
    packet = ""
    while true do
        if string.len(lastRxData) > 512 then
            logF("lastmsg len too long!!!")
            lastRxData = ""
            return lastRxData, queue
        end
        packet, lastRxData = analyzePacket(lastRxData)
        if packet then
            logF("packet", packet:toHex())
        end
        if lastRxData == nil then
            logF("lastmsg no start flag!!!")
            lastRxData = ""
            return lastRxData, queue
        end
        if packet and packet ~= "" then
            packet = msgDecode(packet)
            check = api.XorCheck(packet, #packet - 1)
            if string.byte(packet, #packet) == check then
                packet = string.sub(packet, 1, #packet - 1)
                msgID, msgSn, rxSimID, msgBody = analyzeHead(packet)
                if msgID ~= nil then
                    table.insert(queue, {
                        msgID = msgID,
                        msgSn = msgSn,
                        rxSimID = rxSimID,
                        body = msgBody
                    })
                end
            else
                logF("packet check error", string.byte(packet, #packet), check)
            end
        elseif not packet then
            return lastRxData, queue
        end
    end
end

-- 打包包头和校验码并转义，组织完数据体后，调用本函数打包后发送
-- msgID uint16_t
-- msgSn uint16_t 
-- simID string 6byte
-- msgBody string
-- 输出 string型，输出数据直接用于发送
function air_jt808.air_jt808Head(msgID, msgSn, simID, msgBody)

    local inBuf, check, msgLen
    -- if #simID ~= 6 then
    -- log.info(moduleName, "simID len error", #simID)
    -- end
    if msgBody then
        msgLen = #msgBody
        inBuf = api.NumToBigBin(msgID, 2) .. api.NumToBigBin(msgLen, 2) .. simID .. api.NumToBigBin(msgSn, 2) .. msgBody
    else
        msgLen = 0
        inBuf = api.NumToBigBin(msgID, 2) .. api.NumToBigBin(msgLen, 2) .. simID .. api.NumToBigBin(msgSn, 2)
    end

    inBuf = inBuf .. string.char(api.XorCheck(inBuf))
    return msgEncode(inBuf)
end

-- 注册包数据体
-- sProvinceID uint16_t
-- sCityID uint16_t 
-- pFactoryID string 5byte
-- pDeviceType string 20byte
-- pDeviceID string 7byte
-- uColor uint8_t
-- pCarID string
-- 输出 string型
function air_jt808.makeRegMsg(sProvinceID, sCityID, pFactoryID, pDeviceType, pDeviceID, uColor, pCarID)

    local temp = string.rep("0", 40)
    temp = api.StrToBin(temp)
    if type(pFactoryID) ~= "string" or type(pDeviceType) ~= "string" or type(pDeviceID) ~= "string" or type(pCarID) ~= "string" then
        return nil
    end
    if #pFactoryID < 5 then
        pFactoryID = pFactoryID .. temp
    end

    if #pDeviceType < 20 then
        pDeviceType = pDeviceType .. temp
    end

    if #pDeviceID < 7 then
        pDeviceID = pDeviceID .. temp
    end

    return api.NumToBigBin(sProvinceID, 2) .. api.NumToBigBin(sCityID, 2) .. string.sub(pFactoryID, 1, 5) .. string.sub(pDeviceType, 1, 20) .. string.sub(pDeviceID, 1, 7) .. api.NumToBigBin(uColor, 1) .. pCarID
end

-- 设备应答包数据体
-- lastRxMsgSn uint16_t
-- lastRxMsgID uint16_t 
-- procResult uint8_t
-- 输出 string型
function air_jt808.makeResponseBody(lastRxMsgSn, lastRxMsgID, procResult)
    return api.NumToBigBin(lastRxMsgSn, 2) .. api.NumToBigBin(lastRxMsgID, 2) .. api.NumToBigBin(procResult, 1)
end

-- 透传包回复数据体
-- text string
-- 输出 string型
function air_jt808.makeTransResponseBody(text)
    return api.NumToBigBin(0xFB, 1) .. text
end

-- 基本定位信息包数据体
-- alarm uint32_t
-- status uint32_t
-- lat uint32_t
-- lgt uint32_t
-- high uint16_t
-- speed uint16_t
-- dir uint16_t
-- dateTime string 6byte
-- 输出 string型
function air_jt808.makeLocatBaseInfoMsg(alarm, status, lat, lgt, high, speed, dir, dateTime)
    return api.NumToBigBin(alarm, 4) .. api.NumToBigBin(status, 4) .. api.NumToBigBin(lat, 4) .. api.NumToBigBin(lgt, 4) .. api.NumToBigBin(high, 2) .. api.NumToBigBin(speed, 2) .. api.NumToBigBin(dir, 2) .. dateTime
end

-- 参数包数据体
-- lastRxMsgSn uint16_t
-- paramNum uint8_t
-- paramCode table uint16_t
-- paramValue table string
-- 输出 string型
function air_jt808.makeParamBody(lastRxMsgSn, paramNum, paramCode, paramValue)
    local i, Buf
    Buf = api.NumToBigBin(lastRxMsgSn, 2) .. string.char(paramNum)
    for i = 1, paramNum do
        Buf = Buf .. api.NumToBigBin(paramCode[i], 2) .. string.char(string.len(paramValue[i])) .. paramValue[i]
    end
    return Buf
end

-- 平台应答包数据体解析
-- inData string型
-- 输出
-- lastTxMsgSn 设备发送包的SN uint16_t
-- lastTxMsgID 设备发送包的ID uint16_t
-- procResult 处理结果 uint8_t
function air_jt808.analyzeMonitorResopnse(inData)

    local lastTxMsgID, lastTxMsgSn, procResult
    if #inData < 5 then
        log.error(moduleName, "普通应答内容长度不对", #inData)
        return nil
    end
    lastTxMsgSn = api.BigBinToNum(string.sub(inData, 1, 2), 2)
    lastTxMsgID = api.BigBinToNum(string.sub(inData, 3, 4), 2)
    procResult = string.byte(inData, 5)

    return lastTxMsgSn, lastTxMsgID, procResult
end

-- 平台注册包数据体解析
-- inData string型
-- 输出
-- lastTxMsgSn 设备发送包的SN uint16_t
-- procResult 处理结果 uint8_t
-- authCode 鉴权码 string
function air_jt808.analyzeRegResopnse(inData)

    local lastTxMsgSn, procResult, authCode, Len
    Len = #inData
    if Len < 3 then
        log.error(moduleName, "注册应答长度不对", #inData)
        return nil, nil, nil
    end

    lastTxMsgSn = api.BigBinToNum(string.sub(inData, 1, 2), 2)

    procResult = string.byte(inData, 3)
    if procResult > 0 then
        return lastTxMsgSn, procResult, nil
    end

    authCode = string.sub(inData, 4, #inData)
    return lastTxMsgSn, procResult, authCode
end

-- 平台设备控制包数据体解析
-- inData string型
-- 输出
-- procResult 处理结果 uint8_t
function air_jt808.analyzeDeviceCtrl(inData)
    return string.byte(inData, 1)
end

-- 设备注册包数据体打包
-- msgSn number型，
-- simID string型
-- 输出
-- string 打包好的注册数据包
function air_jt808.regPackage(msgSn, simID)
    local pTxBuf = air_jt808.makeRegMsg(0, 0, "", "", "", 0, string.char(0x00))
    return air_jt808.air_jt808Head(0x0100, msgSn, simID, pTxBuf)
end

-- 设备鉴权包数据体打包
-- msgSn number型
-- simID string型
-- authCode string型
-- 输出
-- string 打包好的鉴权数据包
function air_jt808.authPackage(msgSn, simID, authCode)
    return air_jt808.air_jt808Head(0x0102, msgSn, simID, authCode)
end

-- 设备心跳包数据体打包
-- msgSn number型，
-- simID string型
-- 输出
-- string 打包好的心跳数据包
function air_jt808.heartPackage(msgSn, simID)
    return air_jt808.air_jt808Head(0x0002, msgSn, simID, nil)
end

-- 设备定位包数据体打包
-- msgSn number型
-- simID string型
-- msgBody string型
-- 输出
-- string 打包好的位置数据包
function air_jt808.positionPackage(msgSn, simID, msgBody)
    return air_jt808.air_jt808Head(0x0200, msgSn, simID, msgBody)
end

return air_jt808