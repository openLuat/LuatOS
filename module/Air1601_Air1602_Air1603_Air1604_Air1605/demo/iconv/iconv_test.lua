--[[
@module  iconv_test
@summary 字符编码转换测试模块
@version 1.0
@date    2025.10.27
@author  孟伟
@usage
本模块提供多种字符编码之间的相互转换功能，支持以下编码转换：
1. Unicode小端(ucs2)与GB2312编码互转
2. Unicode大端(ucs2be)与GB2312编码互转
3. Unicode小端(ucs2)与UTF8编码互转
4. Unicode大端(ucs2be)与UTF8编码互转
5. GB2312 编码与 UTF-8 编码之间的转换。


本文件没有对外接口，直接在main.lua中require "iconv_test"就可以加载运行；
]]

--- unicode小端编码 转化为 gb2312编码
-- @string ucs2s unicode小端编码数据
-- @return string data,gb2312编码数据
-- @usage local data = common.ucs2ToGb2312(ucs2s)
function ucs2ToGb2312(ucs2s)
    local cd = iconv.open("gb2312", "ucs2")
    return cd:iconv(ucs2s)
end

--- gb2312编码 转化为 unicode小端编码
-- @string gb2312s gb2312编码数据
-- @return string data,unicode小端编码数据
-- @usage local data = common.gb2312ToUcs2(gb2312s)
function gb2312ToUcs2(gb2312s)
    local cd = iconv.open("ucs2", "gb2312")
    return cd:iconv(gb2312s)
end

--- unicode大端编码 转化为 gb2312编码
-- @string ucs2s unicode大端编码数据
-- @return string data,gb2312编码数据
-- @usage data = common.ucs2beToGb2312(ucs2s)
function ucs2beToGb2312(ucs2s)
    local cd = iconv.open("gb2312", "ucs2be")
    return cd:iconv(ucs2s)
end

--- gb2312编码 转化为 unicode大端编码
-- @string gb2312s gb2312编码数据
-- @return string data,unicode大端编码数据
-- @usage local data = common.gb2312ToUcs2be(gb2312s)
function gb2312ToUcs2be(gb2312s)
    local cd = iconv.open("ucs2be", "gb2312")
    return cd:iconv(gb2312s)
end

--- unicode小端编码 转化为 utf8编码
-- @string ucs2s unicode小端编码数据
-- @return string data,utf8编码数据
-- @usage data = common.ucs2ToUtf8(ucs2s)
function ucs2ToUtf8(ucs2s)
    local cd = iconv.open("utf8", "ucs2")
    return cd:iconv(ucs2s)
end

--- utf8编码 转化为 unicode小端编码
-- @string utf8s utf8编码数据
-- @return string data,unicode小端编码数据
-- @usage local data = common.utf8ToUcs2(utf8s)
function utf8ToUcs2(utf8s)
    local cd = iconv.open("ucs2", "utf8")
    return cd:iconv(utf8s)
end

--- unicode大端编码 转化为 utf8编码
-- @string ucs2s unicode大端编码数据
-- @return string data,utf8编码数据
-- @usage data = common.ucs2beToUtf8(ucs2s)
function ucs2beToUtf8(ucs2s)
    local cd = iconv.open("utf8", "ucs2be")
    return cd:iconv(ucs2s)
end

--- utf8编码 转化为 unicode大端编码
-- @string utf8s utf8编码数据
-- @return string data,unicode大端编码数据
-- @usage local data = common.utf8ToUcs2be(utf8s)
function utf8ToUcs2be(utf8s)
    local cd = iconv.open("ucs2be", "utf8")
    return cd:iconv(utf8s)
end

--- utf8编码 转化为 gb2312编码
-- @string utf8s utf8编码数据
-- @return string data,gb2312编码数据
-- @usage local data = common.utf8ToGb2312(utf8s)
function utf8ToGb2312(utf8s)
    local cd = iconv.open("ucs2", "utf8")
    local ucs2s = cd:iconv(utf8s)
    cd = iconv.open("gb2312", "ucs2")
    return cd:iconv(ucs2s)
end

--- gb2312编码 转化为 utf8编码
-- @string gb2312s gb2312编码数据
-- @return string data,utf8编码数据
-- @usage local data = common.gb2312ToUtf8(gb2312s)
function gb2312ToUtf8(gb2312s)
    local cd = iconv.open("ucs2", "gb2312")
    local ucs2s = cd:iconv(gb2312s)
    cd = iconv.open("utf8", "ucs2")
    return cd:iconv(ucs2s)
end

--------------------------------------------------------------------------------------------------------
--[[
函数名：ucs2ToGb2312
功能  ：unicode小端编码 转化为 gb2312编码,并打印出gb2312编码数据
参数  ：
        ucs2s：unicode小端编码数据,注意输入参数的字节数
返回值：
]]
local function testucs2ToGb2312(ucs2s)
    print("ucs2ToGb2312")
    local gb2312num = ucs2ToGb2312(ucs2s) --调用的是common.ucs2ToGb2312，返回的是编码所对应的字符串
    --print("gb2312  code：",gb2312num)
    print("gb2312  code：", string.toHex(gb2312num))
end

--[[
函数名：gb2312ToUcs2
功能  ：gb2312编码 转化为 unicode十六进制小端编码数据并打印
参数  ：
        gb2312s：gb2312编码数据，注意输入参数的字节数
返回值：
]]
local function testgb2312ToUcs2(gb2312s)
    print("gb2312ToUcs2")
    local ucs2num = gb2312ToUcs2(gb2312s)
    print("unicode little-endian code:" .. string.toHex(ucs2num)) -- 要将二进制转换为十六进制，否则无法输出
end

--[[
函数名：ucs2beToGb2312
功能  ：unicode大端编码 转化为 gb2312编码，并打印出gb2312编码数据,
大端编码数据是与小端编码数据位置调换
参数  ：
        ucs2s：unicode大端编码数据，注意输入参数的字节数
返回值：
]]
local function testucs2beToGb2312(ucs2s)
    print("ucs2beToGb2312")
    local gb2312num = ucs2beToGb2312(ucs2s) -- 转化后的数据直接变成字符可以直接输出
    print("gb2312 code :" .. string.toHex(gb2312num))
end

--[[
函数名：gb2312ToUcs2be
功能  ：gb2312编码 转化为 unicode大端编码，并打印出unicode大端编码
参数  ：
        gb2312s：gb2312编码数据，注意输入参数的字节数
返回值：unicode大端编码数据
]]
function testgb2312ToUcs2be(gb2312s)
    print("gb2312ToUcs2be")
    local ucs2benum = gb2312ToUcs2be(gb2312s)
    print("unicode big-endian code :" .. string.toHex(ucs2benum))
end

--[[
函数名：ucs2ToUtf8
功能  ：unicode小端编码 转化为 utf8编码,并打印出utf8十六进制编码数据
参数  ：
        ucs2s：unicode小端编码数据，注意输入参数的字节数
返回值：
]]
local function testucs2ToUtf8(ucs2s)
    print("ucs2ToUtf8")
    local utf8num = ucs2ToUtf8(ucs2s)
    print("utf8  code:" .. string.toHex(utf8num))
end

--[[
函数名：utf8ToGb2312
功能  ：utf8编码 转化为 gb2312编码,并打印出gb2312编码数据
参数  ：
        utf8s：utf8编码数据，注意输入参数的字节数
返回值：
]]
local function testutf8ToGb2312(utf8s)
    print("utf8ToGb2312")
    local gb2312num = utf8ToGb2312(utf8s)
    print("gb2312 code:" .. string.toHex(gb2312num))
end

--[[
函数名：gb2312ToUtf8
功能  ：gb2312编码 转化为 utf8编码,并打印出utf8编码数据
参数  ：
        gb2312s：gb2312s编码数据，注意输入参数的字节数
返回值：
]]
local function testgb2312ToUtf8(gb2312s)
    print("gb2312ToUtf8")
    local utf8s = gb2312ToUtf8(gb2312s)
    print("utf8s code:" .. utf8s)
end

function iconv_test_fun()
    while 1 do
        sys.wait(10000)
        testucs2ToGb2312(string.fromHex("1162"))   -- "1162"是"我"字的ucs2编码，这里调用了string.fromHex将参数转化为二进制，也就是两个字节。
        testgb2312ToUcs2(string.fromHex("CED2"))   -- "CED2"是"我"字的gb2312编码
        testucs2beToGb2312(string.fromHex("6211")) -- "6211"是"我"字的ucs2be编码
        testgb2312ToUcs2be(string.fromHex("CED2"))
        testucs2ToUtf8(string.fromHex("1162"))
        testutf8ToGb2312(string.fromHex("E68891")) -- "E68891"是"我"字的utf8编码
        testgb2312ToUtf8(string.fromHex("CED2"))
    end
end

sys.taskInit(iconv_test_fun)
