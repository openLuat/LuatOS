-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "JT808"
VERSION = "2.0.0"

--[[
本demo演示使用string.pack与unpack函数，实现JT808 终端注册协议数据生成与解析
]]

--加载sys库
sys = require("sys")

-- Air780E的AT固件默认会为开机键防抖, 导致部分用户刷机很麻烦
if rtos.bsp() == "EC618" and pm and pm.PWK_MODE then
    pm.power(pm.PWK_MODE, false)
end

local netLed = require("netLed")
--GPIO27配置为输出，用作网络指示灯
local LEDA= gpio.setup(27, 0, gpio.PULLUP)

-- 自定义位运算函数
local bit = {}

--终端消息ID
T_COMMON_RSP = 0x0001
T_REGISTER = 0x0100

function bit.bxor(a, b)
    return a ~ b  -- 按位异或
end

--十六进制转二进制
local function hexToBinary(hexStr)
    local binaryData = {}
    for i = 1, #hexStr, 2 do
        local byte = tonumber(hexStr:sub(i, i+1), 16) -- 每两个字符转换为一个字节
        table.insert(binaryData, string.char(byte))
    end
    return table.concat(binaryData) -- 拼接成二进制字符串
end
--字符串转字节数组
local function stringToBytes(hexStr)
    local bytes = {}
    for i = 1, #hexStr, 2 do
        local byteStr = hexStr:sub(i, i+1)
        local byte = tonumber(byteStr, 16)
        table.insert(bytes, byte)
    end
    return bytes
end
--BCD编码
local function encodeBcdNum(d, n)
    if d:len() < n then
        return (string.rep('0', n - d:len()) .. d):fromHex()
    else
        return (d:sub(1, n)):fromHex()
    end
end
--计算异或校验（十六进制字符串）
local function calculateXor(data)
    local sum = 0
     for i = 1, #data, 2 do
        local byte = tonumber(data:sub(i, i+1), 16)

        -- 检查是否转换成功
        if not byte then
           error(string.format("Invalid hex character: '%s' at position %d", byteStr, i))
        end

        -- 打印当前字节的值（十六进制和十进制）
        --print(string.format("当前字节: %s (十进制: %d)", byteStr, byte))

        if not byte then
            error("Invalid hex character in input string!")
        end
        sum = bit.bxor(sum, byte)
        -- 打印异或后的中间结果
        --print(string.format("异或后 sum = %d (十六进制: 0x%X)", sum, sum))
    end
    return sum
end
--
local function calCrc(hexStr)

    -- 解析hexStr转换为十六进制字符数组
    local byteArray = HexOutput(hexStr)

    -- 计算 CRC
    local crc = calculateXor(byteArray)
    log.info("CRCxor:",crc)

    -- 返回 CRC 值
    return crc
end

--将时间转换为BCD格式
function timeToBCD()
    local t = os.date("*t")
    
    -- 转换为BCD格式
    local year = string.format("%02d", t.year % 100)
    local month = string.format("%02d", t.month)
    local day = string.format("%02d", t.day)
    local hour = string.format("%02d", t.hour)
    local min = string.format("%02d", t.min)
    local sec = string.format("%02d", t.sec)
    
    -- 组合BCD格式字符串
    local bcdTime = year .. month .. day .. hour .. min .. sec
    
    return bcdTime
end


--构建通用应答
function cmnRsp(svrSeq, svrId, result)
    return string.pack('>HHb', svrSeq, svrId, result)   
    -- >表示使用大端字节序;  
    -- HH 表示两个 16 位无符号整数（svrSeq 和 svrId）; 
    -- b 表示一个 8 位有符号整数（result）
end
--构建设备注册
function register(ProvinceId,CityId,ManufactureId,TerminalModule,TerminalId,CarColor,CarId)
    local termMd = TerminalModule..string.rep(string.char(0), 16 - (TerminalModule):len())..string.rep(string.char(0), 4)
    --log.info("HexDataByteLength:",#termMd)
    --log.info("HexData is:       ",termMd)
    return string.pack('>HHc5c20c7Bc11',ProvinceId,CityId,ManufactureId,termMd,TerminalId:fromHex(),CarColor,CarId)
end
--构建位置信息汇报
function locRpt(alarm, status, lat, lng, alt, spd, course, tm, extInfo)
    -- 使用 '>iiiiHHH' 格式打包数据
    return string.pack('>iiiiHHH', alarm, status, lat, lng, alt, spd, course)..tm:fromHex().. extInfo
end

function HexOutput(data)
    log.info("HexDataByteLength:",#data)
    local hex = ""
    for i = 1, #data do
        hex = hex.. string.format("%02x", string.byte(data, i))
    end
    log.info("HexData is:       ",hex)
    return hex
end
--封装一个完整的JT808终端注册数据帧
function encodeReg(phoneNo,tSendSeq)
    --消息体
    local msgBody = register(12,123,'10001','GT808','00000000000002',0,'41048063212')
    --消息头
    local msgHead =string.pack('>HH',T_REGISTER,msgBody:len())..encodeBcdNum(phoneNo,12)..tSendSeq
    local curSeq = tSendSeq
    tSendSeq = (tSendSeq == 0xFFFF) and 0 or (tSendSeq + 1)
    --校验码
    HexOutput(msgHead .. msgBody)
    local frame = msgHead .. msgBody
    log.info("encodeReg Frame length is:       ",#frame)
    local crc = calCrc(frame)
    
    --转义
    local s = msgHead .. msgBody .. string.char(crc)
    s = s:gsub('\125', '\125\1') -- 7D -> 7D 01
    s = s:gsub('\126', '\125\2') -- 7E -> 7D 02
    return string.char(0x7E) .. s .. string.char(0x7E), curSeq

end

function decodeCmnRsp(s)

    log.info("hereNow.",s)
    --local start, tail, msg = s:find('^(7E[^7E]+7E)$')
    --local decPacket, msgAttr = {}
-- 检查是否以 7E 开头和结尾
    if not s:match("^7E") or not s:match("7E$") then
        log.warn("prot.decode", "packet does not start or end with 7E")
        return nil
    end

    -- 匹配以 7E 开头和结尾的数据包
    local start, tail, msg = s:find('^(7E.+7E)$')  -- 改为允许中间部分包含 7E
    log.info("start:", start)
    log.info("tail:", tail)
    log.info("msg:", msg)

    if not msg then
        -- 如果未匹配到
        log.warn('prot.decode', 'wait packet complete')
        return nil
    end
    
    --反转义
    msg = msg:gsub('\125\2', '\126') -- 7D 02 -> 7E
    msg = msg:gsub('\125\1', '\125') -- 7D 01 -> 7D

    log.info("msg:", msg,msg:len())

    if msg:len() < 13 then
        log.error('prot.decode', 'packet len is too short')
        return s:sub(tail + 1, -1), nil
    end

    local hexArray = stringToBytes(msg)

    local dataHexStr = msg:sub(3, -5)
    log.info("消息体和其字节长度:", dataHexStr,dataHexStr:len())

    local crcVal = calculateXor(dataHexStr)
    print("XOR校验值:", crcVal)

    if  crcVal ~= hexArray[#hexArray-1] then
        log.error('prot.decode', 'crc value error!')
        return s:sub(tail + 1, -1), nil
    else
        log.info("XOR:校验通过")
    end

    ----------------------------解析消息id
    msgdata = msg:sub(3, 6)

    -- 转换为二进制数据
    local binaryData = hexToBinary(msgdata)

    -- 解析二进制数据
    msgId = string.unpack(">H", binaryData)

    -- 输出结果
    log.info("消息id十六进制:", string.format("0x%04X", msgId))

    ----------------------------解析应答结果
    msgdata = msg:sub(7, 8)

    -- 转换为二进制数据
    local binaryData = hexToBinary(msgdata)

    -- 解析二进制数据
    result = string.unpack(">B", binaryData)

    -- 输出结果
    log.info("结果十六进制:", string.format("0x%02X", result))

    ----------------------------解析鉴权码
    msgdata = msg:sub(9, 10)

    -- 转换为二进制数据
    local binaryData = hexToBinary(msgdata)

    -- 解析二进制数据
    result = string.unpack(">B", binaryData)

    -- 输出结果
    log.info("鉴权码十六进制:", string.format("0x%02X", result))

    ----------------------------解析电话号码
    msgdata = msg:sub(11, 22)

    -- 转换为二进制数据
    local binaryData = hexToBinary(msgdata)

    -- 解析二进制数据
    local b1, b2, b3, b4, b5, b6 = string.unpack(">BBBBBB", binaryData)

    -- 格式化输出为 6 字节的十六进制字符串
    local TerminalPhoneNo = string.format("0x%02X%02X%02X%02X%02X%02X", b1, b2, b3, b4, b5, b6)

    -- 输出电话号码
    log.info("电话号码十六进制:", TerminalPhoneNo)

    ----------------------------解析标头流水号
    msgdata = msg:sub(23, 26)

    -- 转换为二进制数据
    local binaryData = hexToBinary(msgdata)

    -- 解析二进制数据
    local ManualMsgNum = string.unpack(">H", binaryData)

    -- 输出结果
    log.info("标头流水号十六进制:", string.format("0x%04X", ManualMsgNum))

    ----------------------------解析标尾流水号
    msgdata = msg:sub(23, 26)

    -- 转换为二进制数据
    local binaryData = hexToBinary(msgdata)

    -- 解析二进制数据
    local MsgNum = string.unpack(">H", binaryData)

    -- 输出结果
    log.info("标尾流水号十六进制:", string.format("0x%04X", MsgNum))

    ----------------------------解析鉴权码
    msgdata = msg:sub(33, 50)

    -- 转换为二进制数据
    local binaryData = hexToBinary(msgdata)

    local b1, b2, b3, b4, b5, b6, b7, b8, b9 = string.unpack(">BBBBBBBBB", binaryData)

    -- 格式化输出为 6 字节的十六进制字符串
    local JianquanCode = string.format("0x%02X%02X%02X%02X%02X%02X%02X%02X%02X", b1, b2, b3, b4, b5, b6, b7, b8, b9)

    -- 输出结果
    log.info("鉴权码十六进制:", JianquanCode)
end

--新建任务，每休眠2000ms继续一次
sys.taskInit(function()
    
    --实验1：构建立通用应答数据帧，协议可参考JT808协议8.1与8.2
    --输入参数：
    --应答流水号为123，
    --应答 ID为456，
    --结果为1，
    local data = cmnRsp(123, 456, 1)
    HexOutput(data)  --HexDataByteLength:5,HexData is:007b01c801  007b为123，01c8为456，1为1

    --实验2：构建终端注册数据帧，协议可参考JT808协议8.5
    --输入参数：
    --12,                   --省域 ID  WORD
    --123,                  --市县域 ID  WORD
    --'10001',              --制造商 ID  BYTE[5]
    --'GT808'               --终端型号 BYTE[20]
    --'00000000000002',     --终端 ID BYTE[7]
    --0,                    --车牌颜色  BYTE
    --'41048063212')        --车辆标识  STRING  VIN或车牌号均为固定长度，这里假设字符串长度为11
    local data = register(12,123,'10001','GT808','00000000000002',0,'41048063212')
    HexOutput(data)--[HexDataByteLength:]	48，[HexData is:       ]	

    --输出解析：
    --000c，对应12,                   --省域 ID  WORD
    --007b，对应123,                  --市县域 ID  WORD
    --3130303031，对应'10001',              --制造商 ID  BYTE[5]
    --4754383038，对应'GT808'               --终端型号 BYTE[20]，不足字节补0
    --0000000000
    --0000000000
    --0000000000
    --00000000000002 对应'00000000000002',     --终端 ID BYTE[7]
    --000,                    --车牌颜色  BYTE
    --3431303438303633323132，对应'41048063212')        --车辆标识  STRING 

 
    --实验3：构建位置信息汇报数据帧，协议可参考JT808协议8.18
    --输入参数：
    --0, 报警标志 DWORD
    --1, 状态位 DWORD
    --12345678, 纬度 DWORD
    --87654321, 经度 DWORD
    --100, 高程 WORD
    --60, 速度 WORD
    --180, 方向 WORD
    --os.time(), 时间 BCD[6]  YY-MM-DD-hh-mm-ss（GMT+8 时间，本标准中之后涉及的时间均采用此时区）
    --"extra"

    local time = timeToBCD();
    log.info("CurrentTime:       ",time)

    local data = locRpt(0, 1, 12345678, 87654321, 100, 60, 180, time, "extra")
    HexOutput(data)--[HexDataByteLength:]	33,[HexData is:       ]	000000000000000100bc614e05397fb10064003c00b42411241232046578747261
    --输出解析：
    --00000000,对应 0, 报警标志 DWORD，4字节
    --00000001,对应 1, 状态位 DWORD
    --00bc614e,对应 12345678, 纬度 DWORD
    --05397fb1, 对应 87654321, 经度 DWORD
    --0064,对应 100, 高程 WORD
    --003c,对应60, 速度 WORD
    --00b4,对应180, 方向 WORD
    --241124123204,对应时间 BCD[6]  24-11-24-12-32-04
    --6578747261,对应"extra"

    --实验4：封闭一个完整的JT808注册数据帧
    --输入参数：
    --'018068821447'，手机号不足 12位，则在前补充数字，大陆手机号补充数字 0
    --'101'，消息流水号
    local data = encodeReg('018068821447','101')
    HexOutput(data) --[HexDataByteLength:]	64
                    --[HexData is:       ]	7e01000030018068821447313031000c007b3130303031475438303800000000000000000000000000000000000000000002003431303438303633323132627e

    --输出解析：
    --7e，标识位固定为0x7e
    --0100,消息 ID
    --0030,消息体属性
    --018068821447,手机号
    --313031，消息流水号
    --000c007b3130303031475438303800000000000000000000000000000000000000000002003431303438303633323132，注册消息体
    --62，校验
    --7e，标识位固定为0x7e

    --实验5：解析JT808终端注册应答数据帧
    local hexStr = '7E8100000C0404571031660030003000736875616E67776569E07E'
    decodeCmnRsp(hexStr)
end)
-- 这里演示4G模块上网后，会自动点亮网络灯，方便用户判断模块是否正常开机
sys.taskInit(function()
    while true do
        sys.wait(6000)
                if mobile.status() == 1 then
                        gpio.set(27, 1)  
                else
                        gpio.set(27, 0) 
                        mobile.reset()
        end
    end
end)
-- 用户代码已结束---------------------------------------------
-- 运行lua task，只能调用一次，而且必须写在末尾
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
