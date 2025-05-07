local ASCII_CR = 0x0D
local ASCII_LF = 0x0A
local ASCII_0 = 48
local ASCII_9 = 57
local ASCII_A = 65
local ASCII_F = 70
local ASCII_Z = 90
local ASCII_a = 97
local ASCII_f = 102
local ASCII_z = 122
local moduleName = "api"
local logSwitch = false
local function logF(...)
    if logSwitch then
        log.info(moduleName, ...)
    end
end
local api = {}
-- 数组型TABLE转成BIN
function api.ArrayToBin(Array, Len)
    logF("ArrayToBin")
    if Len == nil or Len > #Array then
        Len = #Array
    end
    return string.char(unpack(Array, 1, Len))
end

-- 检查输入的数据是否为全数字字符串，如果是table，则自动转为string
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
    for i = 1, Len do
        local Temp = string.byte(Data, i)

        if Temp >= ASCII_0 and Temp <= ASCII_9 then

        else
            return false
        end
    end
    return true
end

-- 检查输入的数据是否为全数字字母字符串，如果是table，则自动转为string
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

    for i = 1, Len do
        local Temp = string.byte(Data, i)

        if (Temp >= ASCII_0 and Temp <= ASCII_9) or (Temp >= ASCII_a and Temp <= ASCII_f) or (Temp >= ASCII_A and Temp <= ASCII_F) then

        else
            return false
        end
    end
    return true
end

-- 字节流数据转换为可打印字符串，用Cut来分隔开{0xC8, 0x32, 0x9B, 0xFD, 0x0E, 0x01} --> "C8329BFD0E01"
function api.BinToHex(Data, Len, Cut)
    logF("BinToHex")
    local Hex = {}

    if type(Data) == "table" then
        Data = ArrayToBin(Data)
    elseif type(Data) ~= "string" then
        return nil
    end

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

    for i = 1, Len do
        table.insert(Hex, string.upper(string.format("%02x", string.byte(Data, i))) .. (Cut == nil and "" or Cut))
    end
    return table.concat(Hex)

end

function api.BinToDec(Data, Len, Cut)
    logF("BinToDec")
    local Hex = {}

    if type(Data) == "table" then
        Data = ArrayToBin(Data)
    elseif type(Data) ~= "string" then
        return nil
    end

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

    for i = 1, Len do
        table.insert(Hex, string.upper(string.format("%d", string.byte(Data, i))) .. (Cut == nil and "" or Cut))
    end
    return table.concat(Hex)

end

-- 可打印字符串转换为字节流数据,"C8329BFD0E01" --> {0xC8, 0x32, 0x9B, 0xFD, 0x0E, 0x01}
function api.StrToBin(Str, Len)
    logF("StrToBin")
    if type(Str) == "table" then
        Str = api.ArrayToBin(Str)
    elseif type(Str) ~= "string" then
        return nil
    end

    if #Str % 2 > 0 then
        Str = "0" .. Str
    end

    if Len == nil or (Len * 2) > #Str then
        Len = #Str / 2
    end

    local Buf = {}
    local Temp
    for var = 1, Len do
        Temp = string.sub(Str, var * 2 - 1, var * 2)
        Temp = tonumber(Temp, 16)
        table.insert(Buf, Temp)
    end
    return api.ArrayToBin(Buf, Len)
end

-- 表数据数据用10进制，Cut做分割，默认用空格
function api.TableToDecStr(Table, Len, Cut)

    logF("TableToDecStr")

    local Hex = {}
    if type(Table) == "table" then
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
        for i = 1, Len do
            table.insert(Hex, string.format("%d", Table[i]) .. (Cut == nil and " " or Cut))
        end
        return table.concat(Hex)
    else
        return nil
    end
end

-- 数字（默认base16）转BIN,小端格式0x12345678 -> 0x78 0x56 0x34 0x12
function api.NumToLitteBin(Num, Len, Base)

    logF("NumToLitteBin")

    local Buf = {}
    local NumTemp
    if Len == nil then
        Len = 4
    end
    if Base ~= 10 then
        Base = 256
    else
        Base = 100
    end
    if Num == nil then
        Num = 0
    end

    for var = 1, Len do
        NumTemp = Num % Base
        table.insert(Buf, NumTemp)
        Num = Num / Base

    end
    return api.ArrayToBin(Buf, Len)
end

-- BIN转Num,小端格式0x78 0x56 0x34 0x12 -> 0x12345678
function api.LitteBinToNum(Bin, Len)

    logF("LitteBinToNum")

    local Num = 0
    if Len == nil then
        Len = 4
    end
    for i = Len, 1, -1 do
        if string.byte(Bin, i) ~= nil then
            Num = Num * 256
            Num = Num + string.byte(Bin, i)
        end
    end
    return Num
end

-- 数字（默认base16）转BIN,大端格式0x12345678 -> 0x12 0x34 0x56 0x78
function api.NumToBigBin(Num, Len, Base)

    logF("NumToBigBin")

    local Buf = {}
    local NumTemp
    if Len == nil then
        Len = 4
    end
    if Base ~= 10 then
        Base = 256
    else
        Base = 100
    end
    if Num == nil then
        Num = 0
    end
    for var = 1, Len do
        NumTemp = Num % Base
        table.insert(Buf, 1, NumTemp)
        Num = Num // Base
    end
    return api.ArrayToBin(Buf, Len)
end

-- BIN转Num,大端格式0x12 0x34 0x56 0x78 -> 0x12345678
function api.BigBinToNum(Bin, Len)

    logF("BigBinToNum")

    local Num = 0
    if Len == nil then
        Len = 4
    end
    for i = 1, Len do
        if string.byte(Bin, i) ~= nil then
            Num = Num * 256
            Num = Num + string.byte(Bin, i)
        end
    end
    return Num
end

-- 数字（默认base10）转BCD
function api.NumToBCDBin(Num, Len, Base)

    logF("NumToBCDBin")

    local Buf = {}
    local NumTemp
    if Base ~= 16 then
        Base = 100
    else
        Base = 256
    end

    for var = 1, Len do
        NumTemp = Num % Base
        NumTemp = (NumTemp // 10 * 16) + (NumTemp % 10)
        table.insert(Buf, 1, NumTemp)
        Num = Num // Base
    end
    return api.ArrayToBin(Buf, Len)
end

function api.FloatToNum(inStr, decimalNum)

    logF("FloatToNum")

    if type(inStr) ~= "string" then
        return nil
    end
    local integer, fraction = string.match(inStr, "(%d+)%.(%d+)")
    if fraction == nil then
        fraction = ""
    end
    if integer == nil then
        integer = "0"
    end
    fraction = fraction .. string.rep("0", decimalNum)
    fraction = string.sub(fraction, 1, decimalNum)
    return tonumber(integer .. fraction)
end

function api.NumToFloat(Num, integerNum, decimalNum)

    return string.sub(str, 1, integerNum) .. "." .. string.sub(str, integerNum + 1, integerNum + decimalNum)

end

-- 异或校验
function api.XorCheck(Data, Len, Start)
    logF("XorCheck")
    if type(Data) == "table" then
        Data = api.ArrayToBin(Data)
    elseif type(Data) ~= "string" then
        return nil
    end

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

    for i = 1, Len do
        Check = bit.bxor(Check, string.byte(Data, i))
    end

    return Check
end

-- 开平方
function api.Sqrt(a)
    logF("Sqrt")
    local x
    if a == 0 or a == 1 then
        return a
    end -- 特殊处理直接返回
    x = a / 2
    for i = 1, 100 do
        x = (x + a / x) / 2
    end
    return x
end

-- 返回差值的绝对值
function api.Minus(v1, v2)
    logF("Minus")
    return ((v1 > v2) and (v1 - v2) or (v2 - v1))
end

-- 非精确计算GPS坐标差值，输入NTU型数据，西经和南纬为负
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
