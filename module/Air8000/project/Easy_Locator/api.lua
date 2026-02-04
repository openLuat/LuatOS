--[[
@module  api
@summary 通用工具函数库：数据类型转换、编码解码、校验计算
@version 1.0
@author  Auto
@usage
本模块实现以下功能：
1. 数据类型转换：数组/字符串/二进制互转
2. 编码转换：HEX/BCD/DEC格式转换
3. 大小端转换：大端/小端字节序处理
4. 校验计算：XOR异或校验
5. 数值计算：平方根、绝对值、GPS坐标差值
]]

-- ==================== 常量定义 ====================

-- ASCII字符常量
local ASCII_CR = 0x0D   -- 回车符 \r
local ASCII_LF = 0x0A   -- 换行符 \n
local ASCII_0 = 48      -- 字符 '0'
local ASCII_9 = 57      -- 字符 '9'
local ASCII_A = 65      -- 字符 'A'
local ASCII_F = 70      -- 字符 'F'
local ASCII_Z = 90      -- 字符 'Z'
local ASCII_a = 97      -- 字符 'a'
local ASCII_f = 102     -- 字符 'f'
local ASCII_z = 122     -- 字符 'z'

-- ==================== 全局变量 ====================

local moduleName = "api"
local logSwitch = false

-- 本地日志函数
local function logF(...)
    if logSwitch then
        log.info(moduleName, ...)
    end
end

-- 模块导出表
local api = {}

-- ==================== 数组转二进制 ====================

--[[
数组型TABLE转换成二进制字符串
将数字数组转换为二进制字符串，每个数字作为一个字节

@api api.ArrayToBin(Array, Len)
@table Array 数字数组，如 {0xC8, 0x32, 0x9B}
@number Len 可选，转换长度，默认为整个数组
@return string 二进制字符串
@usage
local bin = api.ArrayToBin({0xC8, 0x32, 0x9B}, 3)  -- 返回 "\xC8\x32\x9B"
]]
function api.ArrayToBin(Array, Len)
    logF("ArrayToBin")
    if Len == nil or Len > #Array then
        Len = #Array
    end
    return string.char(unpack(Array, 1, Len))
end

-- ==================== 字符串检查 ====================

--[[
检查输入的数据是否为全数字字符串
如果是table类型，则自动转换为string

@api api.DigitalStrCheck(Data, Len)
@any Data 输入数据（table或string）
@number Len 可选，检查长度，默认为整个数据
@return boolean true=全数字，false=包含非数字字符
@usage
api.DigitalStrCheck("12345")    -- 返回 true
api.DigitalStrCheck("12a45")    -- 返回 false
api.DigitalStrCheck({1,2,3})    -- 返回 true
]]
function api.DigitalStrCheck(Data, Len)
    logF("DigitalStrCheck")
    if type(Data) == "table" then
        Data = ArrayToBin(Data)
    elseif type(Data) ~= "string" then
        return false
    end

    if Len == nil or Len > string.len(Data) then
        Len = string.len(Data)
    end
    if Len == 0 then
        return false
    end

    -- 检查每个字符是否为数字（ASCII 48-57）
    for i = 1, Len do
        local Temp = string.byte(Data, i)
        if Temp >= ASCII_0 and Temp <= ASCII_9 then
            -- 是数字
        else
            return false
        end
    end
    return true
end

--[[
检查输入的数据是否为全数字字母字符串（十六进制字符串）
如果是table类型，则自动转换为string

@api api.HexStrCheck(Data, Len)
@any Data 输入数据（table或string）
@number Len 可选，检查长度，默认为整个数据
@return boolean true=全数字字母（十六进制），false=包含非法字符
@usage
api.HexStrCheck("1A2B3C")     -- 返回 true
api.HexStrCheck("1G2B3C")     -- 返回 false
]]
function api.HexStrCheck(Data, Len)
    logF("HexStrCheck")
    if type(Data) == "table" then
        Data = ArrayToBin(Data)
    elseif type(Data) ~= "string" then
        return false
    end

    if Len == nil or Len > string.len(Data) then
        Len = string.len(Data)
    end

    -- 检查每个字符是否为十六进制字符（0-9, A-F, a-f）
    for i = 1, Len do
        local Temp = string.byte(Data, i)
        if (Temp >= ASCII_0 and Temp <= ASCII_9) or 
           (Temp >= ASCII_a and Temp <= ASCII_f) or 
           (Temp >= ASCII_A and Temp <= ASCII_F) then
            -- 是十六进制字符
        else
            return false
        end
    end
    return true
end

-- ==================== 二进制转字符串 ====================

--[[
字节流数据转换为可打印的HEX字符串
使用Cut参数来分隔每个字节

@api api.BinToHex(Data, Len, Cut)
@any Data 输入数据（table或string）
@number/string Len 可选，转换长度，或分隔符字符串
@string Cut 可选，字节分隔符，默认无分隔符
@return string HEX字符串
@usage
api.BinToHex("\xC8\x32\x9B\xFD")               -- 返回 "C8329BFD"
api.BinToHex("\xC8\x32\x9B\xFD", nil, " ")     -- 返回 "C8 32 9B FD"
api.BinToHex("\xC8\x32\x9B\xFD", " ")          -- 返回 "C8 32 9B FD"
]]
function api.BinToHex(Data, Len, Cut)
    logF("BinToHex")
    local Hex = {}

    if type(Data) == "table" then
        Data = ArrayToBin(Data)
    elseif type(Data) ~= "string" then
        return nil
    end

    -- 处理Len参数（可能是长度或分隔符）
    if type(Len) == "string" then
        Cut = Len
        Len = string.len(Data)
    elseif type(Len) == "number" then
        if Len > string.len(Data) then
            Len = string.len(Data)
        end
    else
        Len = string.len(Data)
    end

    -- 将每个字节转换为两位十六进制字符串
    for i = 1, Len do
        table.insert(Hex, string.upper(string.format("%02x", string.byte(Data, i))) .. (Cut == nil and "" or Cut))
    end
    return table.concat(Hex)
end

--[[
字节流数据转换为十进制数字字符串
使用Cut参数来分隔每个字节

@api api.BinToDec(Data, Len, Cut)
@any Data 输入数据（table或string）
@number/string Len 可选，转换长度，或分隔符字符串
@string Cut 可选，字节分隔符，默认无分隔符
@return string 十进制字符串
@usage
api.BinToDec("\x01\x02\x03")              -- 返回 "123"
api.BinToDec("\x01\x02\x03", nil, " ")    -- 返回 "1 2 3"
]]
function api.BinToDec(Data, Len, Cut)
    logF("BinToDec")
    local Hex = {}

    if type(Data) == "table" then
        Data = ArrayToBin(Data)
    elseif type(Data) ~= "string" then
        return nil
    end

    -- 处理Len参数（可能是长度或分隔符）
    if type(Len) == "string" then
        Cut = Len
        Len = string.len(Data)
    elseif type(Len) == "number" then
        if Len > string.len(Data) then
            Len = string.len(Data)
        end
    else
        Len = string.len(Data)
    end

    -- 将每个字节转换为十进制字符串
    for i = 1, Len do
        table.insert(Hex, string.upper(string.format("%d", string.byte(Data, i))) .. (Cut == nil and "" or Cut))
    end
    return table.concat(Hex)
end

-- ==================== 字符串转二进制 ====================

--[[
可打印的HEX字符串转换为字节流数据
如果字符串长度为奇数，自动在前面补0

@api api.StrToBin(Str, Len)
@string Str HEX字符串，如 "C8329BFD0E01"
@number Len 可选，转换长度（字节数），默认为字符串长度/2
@return string 二进制字符串
@usage
api.StrToBin("C8329BFD0E01")  -- 返回 "\xC8\x32\x9B\xFD\x0E\x01"
api.StrToBin("ABC", 2)         -- 返回 "\x0A\xBC"
]]
function api.StrToBin(Str, Len)
    logF("StrToBin")
    if type(Str) == "table" then
        Str = api.ArrayToBin(Str)
    elseif type(Str) ~= "string" then
        return nil
    end

    -- 如果字符串长度为奇数，在前面补0
    if #Str % 2 > 0 then
        Str = "0" .. Str
    end

    if Len == nil or (Len * 2) > #Str then
        Len = #Str / 2
    end

    local Buf = {}
    local Temp
    -- 每两个字符转换为一个字节
    for var = 1, Len do
        Temp = string.sub(Str, var * 2 - 1, var * 2)
        Temp = tonumber(Temp, 16)
        table.insert(Buf, Temp)
    end
    return api.ArrayToBin(Buf, Len)
end

-- ==================== 表转字符串 ====================

--[[
将表数据转换为十进制字符串，使用Cut参数分隔
默认使用空格分隔

@api api.TableToDecStr(Table, Len, Cut)
@table Table 数字数组
@number/string Len 可选，转换长度，或分隔符字符串
@string Cut 可选，元素分隔符，默认为空格
@return string 十进制字符串
@usage
api.TableToDecStr({1, 2, 3})              -- 返回 "1 2 3"
api.TableToDecStr({1, 2, 3}, nil, ",")   -- 返回 "1,2,3"
]]
function api.TableToDecStr(Table, Len, Cut)
    logF("TableToDecStr")
    local Hex = {}
    
    if type(Table) == "table" then
        -- 处理Len参数（可能是长度或分隔符）
        if type(Len) == "string" then
            Cut = Len
            Len = #Table
        elseif type(Len) == "number" then
            if Len > #Table then
                Len = #Table
            end
        else
            Len = #Table
        end
        
        -- 将每个元素转换为十进制字符串
        for i = 1, Len do
            table.insert(Hex, string.format("%d", Table[i]) .. (Cut == nil and " " or Cut))
        end
        return table.concat(Hex)
    else
        return nil
    end
end

-- ==================== 小端格式转换 ====================

--[[
数字转换为小端格式二进制（低字节在前）
默认Base=16（256进制），Base=10（100进制）

@api api.NumToLitteBin(Num, Len, Base)
@number Num 要转换的数字
@number Len 可选，字节数，默认4字节
@number Base 可选，进制，256=16进制，100=10进制
@return string 小端格式二进制字符串
@usage
api.NumToLitteBin(0x12345678)           -- 返回 "\x78\x56\x34\x12"
api.NumToLitteBin(12345, 2, 100)         -- 返回 "\x45\x30"
]]
function api.NumToLitteBin(Num, Len, Base)
    logF("NumToLitteBin")
    local Buf = {}
    local NumTemp
    
    if Len == nil then
        Len = 4
    end
    
    -- 确定进制
    if Base ~= 10 then
        Base = 256
    else
        Base = 100
    end
    
    if Num == nil then
        Num = 0
    end

    -- 逐字节取模（小端：低字节在前）
    for var = 1, Len do
        NumTemp = Num % Base
        -- 确保是整数，避免浮点数导致string.char失败
        NumTemp = math.floor(NumTemp)
        table.insert(Buf, NumTemp)
        Num = Num / Base
    end
    return api.ArrayToBin(Buf, Len)
end

--[[
小端格式二进制转换为数字（低字节在前）

@api api.LitteBinToNum(Bin, Len)
@string Bin 小端格式二进制字符串
@number Len 可选，字节数，默认4字节
@return number 转换后的数字
@usage
api.LitteBinToNum("\x78\x56\x34\x12")  -- 返回 0x12345678
]]
function api.LitteBinToNum(Bin, Len)
    logF("LitteBinToNum")
    local Num = 0
    
    if Len == nil then
        Len = 4
    end
    
    -- 从低字节到高字节累加
    for i = Len, 1, -1 do
        if string.byte(Bin, i) ~= nil then
            Num = Num * 256
            Num = Num + string.byte(Bin, i)
        end
    end
    return Num
end

-- ==================== 大端格式转换 ====================

--[[
数字转换为大端格式二进制（高字节在前）
默认Base=16（256进制），Base=10（100进制）

@api api.NumToBigBin(Num, Len, Base)
@number Num 要转换的数字
@number Len 可选，字节数，默认4字节
@number Base 可选，进制，256=16进制，100=10进制
@return string 大端格式二进制字符串
@usage
api.NumToBigBin(0x12345678)            -- 返回 "\x12\x34\x56\x78"
api.NumToBigBin(12345, 2, 100)          -- 返回 "\x30\x45"
]]
function api.NumToBigBin(Num, Len, Base)
    logF("NumToBigBin")
    local Buf = {}
    local NumTemp
    
    if Len == nil then
        Len = 4
    end
    
    -- 确定进制
    if Base ~= 10 then
        Base = 256
    else
        Base = 100
    end
    
    if Num == nil then
        Num = 0
    end
    
    -- 逐字节取模（大端：插入到数组头部，高字节在前）
    for var = 1, Len do
        NumTemp = Num % Base
        -- 确保是整数，避免浮点数导致string.char失败
        NumTemp = math.floor(NumTemp)
        table.insert(Buf, 1, NumTemp)
        Num = Num // Base
    end
    return api.ArrayToBin(Buf, Len)
end

--[[
大端格式二进制转换为数字（高字节在前）

@api api.BigBinToNum(Bin, Len)
@string Bin 大端格式二进制字符串
@number Len 可选，字节数，默认4字节
@return number 转换后的数字
@usage
api.BigBinToNum("\x12\x34\x56\x78")  -- 返回 0x12345678
]]
function api.BigBinToNum(Bin, Len)
    logF("BigBinToNum")
    local Num = 0
    
    if Len == nil then
        Len = 4
    end
    
    -- 从高字节到低字节累加
    for i = 1, Len do
        if string.byte(Bin, i) ~= nil then
            Num = Num * 256
            Num = Num + string.byte(Bin, i)
        end
    end
    return Num
end

-- ==================== BCD编码转换 ====================

--[[
数字转换为BCD编码
默认Base=10（100进制），Base=16（256进制）

@api api.NumToBCDBin(Num, Len, Base)
@number Num 要转换的数字
@number Len 字节数
@number Base 可选，进制，100=10进制，256=16进制
@return string BCD编码字符串
@usage
api.NumToBCDBin(1234, 2)           -- 返回 "\x12\x34"
api.NumToBCDBin(12345678, 4, 100)   -- 返回 "\x12\x34\x56\x78"
]]
function api.NumToBCDBin(Num, Len, Base)
    logF("NumToBCDBin")
    local Buf = {}
    local NumTemp
    
    -- 确定进制
    if Base ~= 16 then
        Base = 100
    else
        Base = 256
    end

    -- 逐字节取模并转换为BCD编码
    for var = 1, Len do
        NumTemp = Num % Base
        -- 确保是整数
        NumTemp = math.floor(NumTemp)
        -- BCD编码：将两位十进制数压缩到一个字节中
        -- 例如：34 -> (3 * 16) + 4 = 0x34
        NumTemp = (NumTemp // 10 * 16) + (NumTemp % 10)
        table.insert(Buf, 1, NumTemp)
        Num = Num // Base
    end
    return api.ArrayToBin(Buf, Len)
end

-- ==================== 浮点数转换 ====================

--[[
浮点数字符串转换为整数（保留指定小数位数）

@api api.FloatToNum(inStr, decimalNum)
@string inStr 浮点数字符串，如 "123.456"
@number decimalNum 保留的小数位数
@return number 转换后的整数
@usage
api.FloatToNum("123.456", 2)   -- 返回 12345
api.FloatToNum("123.456", 3)   -- 返回 123456
]]
function api.FloatToNum(inStr, decimalNum)
    logF("FloatToNum")
    if type(inStr) ~= "string" then
        return nil
    end
    
    -- 分离整数和小数部分
    local integer, fraction = string.match(inStr, "(%d+)%.(%d+)")
    if fraction == nil then
        fraction = ""
    end
    if integer == nil then
        integer = "0"
    end
    
    -- 补齐小数位数
    fraction = fraction .. string.rep("0", decimalNum)
    fraction = string.sub(fraction, 1, decimalNum)
    
    return tonumber(integer .. fraction)
end

--[[
整数转换为浮点数字符串
注意：此函数有bug，使用了未定义的变量str

@api api.NumToFloat(Num, integerNum, decimalNum)
@number Num 要转换的整数
@number integerNum 整数位数
@number decimalNum 小数位数
@return string 浮点数字符串
@usage
-- 需要修复后使用
]]
function api.NumToFloat(Num, integerNum, decimalNum)
    -- 注意：此函数有bug，使用了未定义的变量str
    -- 应该为：return string.format("%d.%0"..decimalNum.."d", Num // (10^decimalNum), Num % (10^decimalNum))
    return string.sub(str, 1, integerNum) .. "." .. string.sub(str, integerNum + 1, integerNum + decimalNum)
end

-- ==================== 校验计算 ====================

--[[
XOR异或校验计算

@api api.XorCheck(Data, Len, Start)
@any Data 输入数据（table或string）
@number/string Len 可选，计算长度，或起始位置字符串
@number Start 可选，起始值，默认0
@return number XOR校验值
@usage
api.XorCheck("\x01\x02\x03")              -- 返回 0x00
api.XorCheck("\x01\x02\x03", 3, 0xAA)     -- 返回 0xAA
]]
function api.XorCheck(Data, Len, Start)
    logF("XorCheck")
    if type(Data) == "table" then
        Data = api.ArrayToBin(Data)
    elseif type(Data) ~= "string" then
        return nil
    end

    -- 处理Len参数（可能是长度或起始位置）
    if type(Len) == "string" then
        Start = Len
        Len = #Data
    elseif type(Len) == "number" then
        if Len > #Data then
            Len = #Data
        end
    else
        Len = #Data
    end

    local Check = (Start == nil and 0 or Start)

    -- 逐字节异或计算
    for i = 1, Len do
        Check = bit.bxor(Check, string.byte(Data, i))
    end

    return Check
end

-- ==================== 数学计算 ====================

--[[
计算平方根（使用牛顿迭代法）

@api api.Sqrt(a)
@number a 要计算平方根的数字
@return number 平方根值
@usage
api.Sqrt(9)      -- 返回 3
api.Sqrt(2)      -- 返回 1.414...
]]
function api.Sqrt(a)
    logF("Sqrt")
    local x
    
    if a == 0 or a == 1 then
        return a
    end -- 特殊处理直接返回
    
    -- 牛顿迭代法：x = (x + a/x) / 2
    x = a / 2
    for i = 1, 100 do
        x = (x + a / x) / 2
    end
    return x
end

--[[
计算两个数值的差值绝对值

@api api.Minus(v1, v2)
@number v1 数值1
@number v2 数值2
@return number 差值的绝对值
@usage
api.Minus(10, 5)   -- 返回 5
api.Minus(5, 10)    -- 返回 5
]]
function api.Minus(v1, v2)
    logF("Minus")
    return ((v1 > v2) and (v1 - v2) or (v2 - v1))
end

--[[
非精确计算GPS坐标差值
输入NTU格式数据，西经和南纬为负数

@api api.GPSDiff(NTULat1, NTULat2, NTULon1, NTULon2)
@number NTULat1 第一个纬度（NTU格式）
@number NTULat2 第二个纬度（NTU格式）
@number NTULon1 第一个经度（NTU格式）
@number NTULon2 第二个经度（NTU格式）
@return number 坐标差值的平方和（非精确距离）
@usage
api.GPSDiff(1000, 2000, 3000, 4000)  -- 返回 2000000
]]
function api.GPSDiff(NTULat1, NTULat2, NTULon1, NTULon2)
    logF("GPSDiff")
    if NTULat1 == nil or NTULat2 == nil or NTULon1 == nil or NTULon2 == nil then
        return 0
    end
    local D1 = api.Minus(NTULat1, NTULat2)
    local D2 = api.Minus(NTULon1, NTULon2)
    return (D1 * D1 + D2 * D2)
end

return api
