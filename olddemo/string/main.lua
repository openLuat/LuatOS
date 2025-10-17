
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "strtest"
VERSION = "2.0.0"

--[[
本demo演示 string字符串的基本操作
1. lua的字符串是带长度, 这意味着, 它不依赖0x00作为结束字符串, 可以包含任意数据
2. lua的字符串是不可变的, 就不能直接修改字符串的一个字符, 修改字符会返回一个新的字符串
]]

-- sys库是标配
_G.sys = require("sys")

sys.taskInit(function ()
    sys.wait(1000) -- 免得看不到日志
    local tmp

    ----------------------------------------------
    --================================================
    -- 字符串的声明和生成
    --================================================

    -- 常量声明
    local str = "123455" 
    log.info("str", str)

    -- 合成式
    str = string.char(0x31, 0x32, 0x33, 0x34)
    log.info("str", str)
    -- lua的字符串可以包含任意数据, 包括 0x00
    str = string.char(0x12, 0x00, 0xF1, 0x3A)
    log.info("str", str:toHex()) -- 注意, 这里用toHex(), 因为包含了不可见字符

    -- 使用转义字符
    str = "\x00\x12ABC"
    log.info("str", str:toHex()) -- 注意, 这里用toHex(), 因为包含了不可见字符
    str = "ABC\r\n\t"
    log.info("str", str:toHex()) -- 注意, 这里用toHex(), 因为包含了不可见字符


    -- 解析生成
    str = string.fromHex("AABB00EE")
    log.info("str", str:toHex())
    str = string.fromHex("393837363433")
    log.info("str", #str, str)

    -- 连接字符串, 操作符 ".."
    str = "123" .. "," .. "ABC"
    log.info("str", #str, str)

    -- 格式化生成
    str = string.format("%s,%d,%f", "123", 45678, 1.5)
    log.info("str", #str, str)


    --================================================
    -- 字符串的解析与处理
    --================================================
    -- 获取长度
    str = "1234567"
    log.info("str", #str)
    -- 获取字符串的HEX字符串显示
    log.info("str", str:toHex())

    -- 获取指定位置的值, 注意lua的下标是1开始的
    str = "123ddss"
    log.info("str[1]", str:byte(1))
    log.info("str[4]", str:byte(4))
    log.info("str[1]", string.byte(str, 1))
    log.info("str[4]", string.byte(str, 4))

    -- 按字符串分割
    str = "12,2,3,4,5"
    tmp = str:split(",")
    log.info("str.split", #tmp, tmp[1], tmp[3])
    tmp = string.split(str, ",") -- 与前面的等价
    log.info("str.split", #tmp, tmp[1], tmp[3])
    str = "/tmp//def/1234/"
    tmp = str:split("/")
    log.info("str.split", #tmp, json.encode(tmp))
    -- 2023.04.11新增的, 可以保留空的分割片段
    tmp = str:split("/", true) 
    log.info("str.split", #tmp, json.encode(tmp))

    -- 更多资料
    -- https://wiki.luatos.com/develop/hex_string.html
    -- https://wiki.luatos.com/_static/lua53doc/manual.html#3.4
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
