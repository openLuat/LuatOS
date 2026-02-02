--[[
@module  jt808
@summary JT808协议实现模块：定位终端与平台通信协议
@version 1.0
@author  Auto
@usage
本模块实现以下功能：
1. 消息编码/解码：处理JT808协议的特殊转义字符
2. 协议解析：解析平台下发的控制指令和应答
3. 消息封装：封装设备上报的定位、注册、鉴权等数据
4. 校验计算：XOR校验确保数据完整性

JT808协议特点：
- 起始/结束标识符：0x7E
- 转义规则：
  * 0x7D -> 0x7D 0x01
  * 0x7E -> 0x7D 0x02
- 校验方式：异或校验（XOR Check）
- 字节序：大端模式（Big-Endian）
]]

local moduleName = "jt808"
local jt808 = {}
local logSwitch = false

-- 本地日志函数
local function logF(...)
    if logSwitch then
        log.info(moduleName, ...)
    end
end

-- ==================== 数据转义 ====================

--[[
发送数据转义处理
对JT808协议的特殊字符进行转义

转义规则：
- 0x7D -> 0x7D 0x01
- 0x7E -> 0x7D 0x02

最后添加起始/结束标识符 0x7E

@api jt808.msgEncode(inData)
@string inData 原始数据
@return string 转义后的数据（包含0x7E标识符）
@local
]]
local function msgEncode(inData)
    local oldString = string.char(0x7d)
    local newString = string.char(0x7d) .. string.char(0x01)
    inData = string.gsub(inData, oldString, newString)
    
    oldString = string.char(0x7e)
    newString = string.char(0x7d) .. string.char(0x02)
    inData = string.gsub(inData, oldString, newString)
    
    return oldString .. inData .. oldString
end

--[[
接收数据转义恢复
将转义后的数据还原为原始数据

转义恢复规则：
- 0x7D 0x02 -> 0x7E
- 0x7D 0x01 -> 0x7D

@api jt808.msgDecode(inData)
@string inData 转义后的数据（不包含0x7E标识符）
@return string 原始数据
@local
]]
local function msgDecode(inData)
    local oldString = string.char(0x7d) .. string.char(0x02)
    local newString = string.char(0x7e)
    inData = string.gsub(inData, oldString, newString)
    
    oldString = string.char(0x7d) .. string.char(0x01)
    newString = string.char(0x7d)
    return string.gsub(inData, oldString, newString)
end

-- ==================== 协议头解析 ====================

--[[
接收协议头解析
解析JT808协议头（12字节）

协议头结构（大端序）：
- Word(2): 消息ID
- Word(2): 消息体属性（包含长度）
- BCD(6): 终端手机号/设备ID
- Word(2): 消息流水号

@api jt808.analyzeHead(inData)
@string inData 协议头数据体（不含0x7E标识符）
@return number,msgID 消息ID
@return number,msgSn 消息流水号
@return string,simID 设备ID（6字节）
@return string,msgBuf 消息体数据
@local
]]
local function analyzeHead(inData)
    local msgID, msgSn, simID, msgLen, Len, i, msgBuf
    
    if type(inData) ~= "string" then
        return nil
    end
    Len = #inData

    -- 解析消息ID（2字节，大端）
    msgID = api.BigBinToNum(string.sub(inData, 1, 2), 2)
    
    -- 解析消息体属性（2字节，大端）
    msgLen = api.BigBinToNum(string.sub(inData, 3, 4), 2)

    -- 验证消息体长度
    if msgLen ~= (Len - 12) then
        log.error(moduleName, "协议头长度不正确", msgLen, Len - 12)
        return nil
    end
    
    -- 解析设备ID（6字节）
    simID = string.sub(inData, 5, 10)
    
    -- 解析消息流水号（2字节，大端）
    msgSn = api.BigBinToNum(string.sub(inData, 11, 12), 2)
    
    -- 提取消息体
    msgBuf = string.sub(inData, 13, #inData)

    return msgID, msgSn, simID, msgBuf
end

-- ==================== 数据包解析 ====================

--[[
接收数据包提取
从接收缓冲区中提取完整的数据包

功能：
1. 查找起始标识符 0x7E
2. 查找结束标识符 0x7E
3. 提取完整数据包和剩余数据

@api jt808.analyzePacket(inData)
@string inData 接收缓冲区数据
@return string,packet 完整的数据包（不包含0x7E标识符）
@return string,lastData 剩余的未处理数据
@local
]]
local function analyzePacket(inData)
    local packet, lastData
    local matchByte = string.char(0x7e)
    local Pos = string.find(inData, matchByte)

    -- 找不到开始标识符
    if Pos == nil then
        return nil, nil
    end

    -- 截取从开始标识符之后的数据
    inData = string.sub(inData, Pos + 1, #inData)
    Pos = string.find(inData, matchByte)

    -- 找不到结束标识符
    if Pos == nil then
        return nil, inData
    end

    -- 提取完整数据包和剩余数据
    packet = string.sub(inData, 1, Pos - 1)
    lastData = string.sub(inData, Pos, #inData)
    return packet, lastData
end

-- ==================== 接收数据解析 ====================

--[[
客户端接收数据解析
从接收缓冲区解析所有完整的JT808数据包

功能：
1. 循环提取完整数据包
2. 转义恢复数据
3. XOR校验验证
4. 解析协议头
5. 返回消息队列

@api jt808.rxAnalyze(lastRxData)
@string lastRxData 上次剩余的接收数据
@return string,lastRxData 剩余的未处理数据
@return table,queue 消息队列，每个元素包含：{msgID, msgSn, rxSimID, body}
]]
function jt808.rxAnalyze(lastRxData)
    local lastRxMsgSn = 0
    local queue = {}
    local result, msgID, msgSn, msgBody, rxSimID, inData, packet, check
    
    logF("rxdata", #lastRxData, api.BinToHex(lastRxData, " "))
    packet = ""
    
    while true do
        -- 数据长度超过限制，清空缓冲区
        if string.len(lastRxData) > 512 then
            logF("lastmsg len too long!!!")
            lastRxData = ""
            return lastRxData, queue
        end
        
        -- 提取数据包
        packet, lastRxData = analyzePacket(lastRxData)
        if packet then
            logF("packet", packet:toHex())
        end
        
        -- 无效数据
        if lastRxData == nil then
            logF("lastmsg no start flag!!!")
            lastRxData = ""
            return lastRxData, queue
        end
        
        -- 处理有效数据包
        if packet and packet ~= "" then
            -- 转义恢复
            packet = msgDecode(packet)
            
            -- XOR校验
            check = api.XorCheck(packet, #packet - 1)
            if string.byte(packet, #packet) == check then
                -- 移除校验字节
                packet = string.sub(packet, 1, #packet - 1)
                
                -- 解析协议头
                msgID, msgSn, rxSimID, msgBody = analyzeHead(packet)
                if msgID ~= nil then
                    -- 添加到消息队列
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
            -- 数据包不完整，返回等待后续数据
            return lastRxData, queue
        end
    end
end

-- ==================== 协议头封装 ====================

--[[
JT808协议头封装
组织消息头并添加校验码，最后转义

协议头结构（大端序）：
- Word(2): 消息ID
- Word(2): 消息体属性（包含长度）
- BCD(6): 终端手机号/设备ID
- Word(2): 消息流水号
- Byte(1): 校验码（XOR）

@api jt808.jt808Head(msgID, msgSn, simID, msgBody)
@number msgID 消息ID（uint16_t）
@number msgSn 消息流水号（uint16_t）
@string simID 设备ID（6字节）
@string msgBody 可选，消息体数据
@return string 完整的JT808消息（包含0x7E标识符）
@usage
local packet = jt808.jt808Head(0x0200, 1, simID, body)
]]
function jt808.jt808Head(msgID, msgSn, simID, msgBody)
    local inBuf, check, msgLen
    
    -- 组织消息头+消息体
    if msgBody then
        msgLen = #msgBody
        inBuf = api.NumToBigBin(msgID, 2) .. api.NumToBigBin(msgLen, 2) .. simID .. api.NumToBigBin(msgSn, 2) .. msgBody
    else
        msgLen = 0
        inBuf = api.NumToBigBin(msgID, 2) .. api.NumToBigBin(msgLen, 2) .. simID .. api.NumToBigBin(msgSn, 2)
    end

    -- 添加XOR校验码
    inBuf = inBuf .. string.char(api.XorCheck(inBuf))
    
    -- 转义处理
    return msgEncode(inBuf)
end

-- ==================== 消息体封装 ====================

--[[
注册消息体封装
0x0100 终端注册

消息体结构：
- Word(2): 省域ID
- Word(2): 市县域ID
- String(5): 厂商ID
- String(20): 设备型号
- String(7): 设备ID
- Byte(1): 车辆颜色
- String: 车辆颜色（可选）

@api jt808.makeRegMsg(sProvinceID, sCityID, pFactoryID, pDeviceType, pDeviceID, uColor, pCarID)
@number sProvinceID 省域ID（uint16_t）
@number sCityID 市县域ID（uint16_t）
@string pFactoryID 厂商ID（5字节）
@string pDeviceType 设备型号（20字节）
@string pDeviceID 设备ID（7字节）
@number uColor 车辆颜色（uint8_t）
@string pCarID 可选，车辆颜色
@return string 注册消息体
]]
function jt808.makeRegMsg(sProvinceID, sCityID, pFactoryID, pDeviceType, pDeviceID, uColor, pCarID)
    -- 填充字符串到指定长度
    local temp = string.rep("0", 40)
    temp = api.StrToBin(temp)
    
    -- 参数类型检查
    if type(pFactoryID) ~= "string" or type(pDeviceType) ~= "string" or type(pDeviceID) ~= "string" or type(pCarID) ~= "string" then
        return nil
    end
    
    -- 填充厂商ID到5字节
    if #pFactoryID < 5 then
        pFactoryID = pFactoryID .. temp
    end

    -- 填充设备型号到20字节
    if #pDeviceType < 20 then
        pDeviceType = pDeviceType .. temp
    end

    -- 填充设备ID到7字节
    if #pDeviceID < 7 then
        pDeviceID = pDeviceID .. temp
    end

    -- 组装注册消息体
    return api.NumToBigBin(sProvinceID, 2) .. api.NumToBigBin(sCityID, 2) .. 
           string.sub(pFactoryID, 1, 5) .. string.sub(pDeviceType, 1, 20) .. 
           string.sub(pDeviceID, 1, 7) .. api.NumToBigBin(uColor, 1) .. pCarID
end

--[[
通用应答消息体封装
0x0001 平台通用应答

@api jt808.makeResponseBody(lastRxMsgSn, lastRxMsgID, procResult)
@number lastRxMsgSn 对应的平台消息流水号（uint16_t）
@number lastRxMsgID 对应的平台消息ID（uint16_t）
@number procResult 处理结果（uint8_t）
@return string 应答消息体
]]
function jt808.makeResponseBody(lastRxMsgSn, lastRxMsgID, procResult)
    return api.NumToBigBin(lastRxMsgSn, 2) .. api.NumToBigBin(lastRxMsgID, 2) .. api.NumToBigBin(procResult, 1)
end

--[[
透传消息体回复
0x0900 数据下行透传

@api jt808.makeTransResponseBody(text)
@string text 透传文本数据
@return string 透传回复消息体
]]
function jt808.makeTransResponseBody(text)
    return api.NumToBigBin(0xFB, 1) .. text
end

--[[
位置信息汇报消息体封装
0x0200 位置信息汇报

@api jt808.makeLocatBaseInfoMsg(alarm, status, lat, lgt, high, speed, dir, dateTime)
@number alarm 报警标识（uint32_t）
@number status 状态（uint32_t）
@number lat 纬度（uint32_t，单位：1/1000000度）
@number lgt 经度（uint32_t，单位：1/1000000度）
@number high 海拔高度（uint16_t，单位：米）
@number speed 速度（uint16_t，单位：1/10km/h）
@number dir 方向（uint16_t，单位：1度）
@string dateTime 时间（6字节，BCD格式，YYMMDDHHMMSS）
@return string 位置信息消息体
]]
function jt808.makeLocatBaseInfoMsg(alarm, status, lat, lgt, high, speed, dir, dateTime)
    return api.NumToBigBin(alarm, 4) .. api.NumToBigBin(status, 4) .. 
           api.NumToBigBin(lat, 4) .. api.NumToBigBin(lgt, 4) .. 
           api.NumToBigBin(high, 2) .. api.NumToBigBin(speed, 2) .. 
           api.NumToBigBin(dir, 2) .. dateTime
end

--[[
参数设置消息体封装

@api jt808.makeParamBody(lastRxMsgSn, paramNum, paramCode, paramValue)
@number lastRxMsgSn 平台消息流水号（uint16_t）
@number paramNum 参数数量（uint8_t）
@table paramCode 参数ID数组（uint16_t）
@table paramValue 参数值数组（string）
@return string 参数设置消息体
]]
function jt808.makeParamBody(lastRxMsgSn, paramNum, paramCode, paramValue)
    local i, Buf
    Buf = api.NumToBigBin(lastRxMsgSn, 2) .. string.char(paramNum)
    for i = 1, paramNum do
        Buf = Buf .. api.NumToBigBin(paramCode[i], 2) .. string.char(string.len(paramValue[i])) .. paramValue[i]
    end
    return Buf
end

-- ==================== 平台应答解析 ====================

--[[
平台通用应答解析
0x8001 平台通用应答

@api jt808.analyzeMonitorResopnse(inData)
@string inData 应答消息体
@return number,lastTxMsgSn 设备发送的消息流水号
@return number,lastTxMsgID 设备发送的消息ID
@return number,procResult 处理结果（0=成功，其他=失败）
]]
function jt808.analyzeMonitorResopnse(inData)
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

--[[
平台注册应答解析
0x8100 终端注册应答

@api jt808.analyzeRegResopnse(inData)
@string inData 注册应答消息体
@return number,lastTxMsgSn 设备发送的消息流水号
@return number,procResult 注册结果（0=成功，其他=失败）
@return string,authCode 鉴权码（成功时返回，失败时返回nil）
]]
function jt808.analyzeRegResopnse(inData)
    local lastTxMsgSn, procResult, authCode, Len
    Len = #inData
    
    if Len < 3 then
        log.error(moduleName, "注册应答长度不对", #inData)
        return nil, nil, nil
    end

    lastTxMsgSn = api.BigBinToNum(string.sub(inData, 1, 2), 2)
    procResult = string.byte(inData, 3)
    
    if procResult > 0 then
        -- 注册失败
        return lastTxMsgSn, procResult, nil
    end

    -- 注册成功，返回鉴权码
    authCode = string.sub(inData, 4, #inData)
    return lastTxMsgSn, procResult, authCode
end

--[[
平台设备控制指令解析

@api jt808.analyzeDeviceCtrl(inData)
@string inData 设备控制指令消息体
@return number 控制指令
]]
function jt808.analyzeDeviceCtrl(inData)
    return string.byte(inData, 1)
end

-- ==================== 消息封装接口 ====================

--[[
设备注册消息封装
消息ID: 0x0100

@api jt808.regPackage(msgSn, simID)
@number msgSn 消息流水号
@string simID 设备ID（6字节）
@return string 完整的注册消息（包含协议头）
]]
function jt808.regPackage(msgSn, simID)
    local pTxBuf = jt808.makeRegMsg(0, 0, "", "", "", 0, string.char(0x00))
    return jt808.jt808Head(0x0100, msgSn, simID, pTxBuf)
end

--[[
设备鉴权消息封装
消息ID: 0x0102

@api jt808.authPackage(msgSn, simID, authCode)
@number msgSn 消息流水号
@string simID 设备ID（6字节）
@string authCode 鉴权码
@return string 完整的鉴权消息（包含协议头）
]]
function jt808.authPackage(msgSn, simID, authCode)
    return jt808.jt808Head(0x0102, msgSn, simID, authCode)
end

--[[
设备心跳消息封装
消息ID: 0x0002

@api jt808.heartPackage(msgSn, simID)
@number msgSn 消息流水号
@string simID 设备ID（6字节）
@return string 完整的心跳消息（包含协议头）
]]
function jt808.heartPackage(msgSn, simID)
    return jt808.jt808Head(0x0002, msgSn, simID, nil)
end

--[[
设备位置信息汇报消息封装
消息ID: 0x0200

@api jt808.positionPackage(msgSn, simID, msgBody)
@number msgSn 消息流水号
@string simID 设备ID（6字节）
@string msgBody 位置信息消息体
@return string 完整的位置信息消息（包含协议头）
]]
function jt808.positionPackage(msgSn, simID, msgBody)
    return jt808.jt808Head(0x0200, msgSn, simID, msgBody)
end

return jt808
