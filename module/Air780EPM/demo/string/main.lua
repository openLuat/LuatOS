
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
    log.info("str", str)														--日志输出：123455

    -- 合成式
    str = string.char(0x31, 0x32, 0x33, 0x34)  --0x31为字符 1的ASCII码
    log.info("str", str)           												--日志输出：1234                   
    -- lua的字符串可以包含任意数据, 包括 0x00
    str = string.char(0x12, 0x00, 0xF1, 0x3A)
    log.info("str", str:toHex()) -- 注意, 这里用toHex(), 因为包含了不可见字符   --日志输出：1200F13A	8（其中8为输出字符串长度）
    -- 使用转义字符
    str = "\x00\x12ABC"			 -- 字符串中的\x表示十六进制转义序列								
    log.info("str", str:toHex()) -- 注意, 这里用toHex(), 因为包含了不可见字符   --日志输出：0012414243	10 （其中41，42，43分别分字符 ABC的ASCII值的十六进制形式，10为输出字符串长度）
    str = "ABC\r\n\t"
    log.info("str", str:toHex()) -- 注意, 这里用toHex(), 因为包含了不可见字符   --日志输出：4142430D0A09	12（其中0D为\r回车键值的ASCII值的十六进制形式，
	                                                                            --0A为\n换行键值的ASCII值的十六进制形式，\t 是一个转义字符，表示一个水平制表符（Tab））



    -- 解析生成
    str = string.fromHex("AABB00EE")											
    log.info("str", str:toHex())												--日志输出：AABB00EE	8
    str = string.fromHex("393837363433")       --将字符串转换为十六进制形式
    log.info("str", #str, str)												    --日志输出：6	987643（其中6为输出字符长度，987643为输出字符串）

    -- 连接字符串, 操作符 ".."
    str = "123" .. "," .. "ABC"  --将3段字符串连接起来
    log.info("str", #str, str)												    --日志输出：7	123,ABC（其中7为输出字符长度，123,ABC为连接后的字符串）


    -- 格式化生成
    str = string.format("%s,%d,%f", "123", 45678, 1.5)		--格式化输出，	%s为字符串输出，%d为十进制输出，%f为浮点形式输出			
    log.info("str", #str, str)													--日志输出：18	123,45678,1.500000


    --================================================
    -- 字符串的解析与处理
    --================================================
    -- 获取长度
    str = "1234567"
    log.info("str", #str)														--日志输出：7为字符串长度
    -- 获取字符串的HEX字符串显示
    log.info("str", str:toHex())												--日志输出：31323334353637	14（用字符格式输出十六进制）

    -- 获取指定位置的值, 注意lua的下标是1开始的
    str = "123ddss"
    log.info("str[1]", str:byte(1))                                             --日志输出：49	 （字符1，对应十进制ASCII值）
    log.info("str[4]", str:byte(4))												--日志输出: 100	 （字符d，对应十进制ASCII值）
    log.info("str[1]", string.byte(str, 1))										--日志输出：49   （str位置1的字符，也是数字1）
    log.info("str[4]", string.byte(str, 4))										--日志输出: 100	 （str位置4的字符，也是数字d）

    -- 按字符串分割
    str = "12,2,3,4,5"
    tmp = str:split(",")
    log.info("str.split", #tmp, tmp[1], tmp[3])									--日志输出：5	12	3
    tmp = string.split(str, ",") -- 与前面的等价
    log.info("str.split", #tmp, tmp[1], tmp[3])                                 --日志输出：5	12	3
    str = "/tmp//def/1234/"
    tmp = str:split("/")
    log.info("str.split", #tmp, json.encode(tmp))								--日志输出：3	["tmp","def","1234"]

    -- 2023.04.11新增的, 可以保留空的分割片段
	--在 Lua 中，str:split("/", true) 语句表示将字符串 str 按照字符 "/" 进行分割，并且 true 参数通常用于表示保留空字符串（这取决于具体的 split 函数实现，因为 Lua 标准库中没有内置的 split 函数）。根据你的描述，输出结果是 6 ["","tmp","","def","1234",""]。这是因为：
    --假设 str 是 "/tmp//def/1234/"，在这种情况下，字符串以 "/" 开头和结尾，并且有连续的 "/"。
    --split 函数将字符串分割成多个部分，每个 "/" 都会作为一个分割符。
    --因为 true 参数表示保留空字符串，所以在分割过程中，连续的 "/" 和开头、结尾的 "/" 都会导致空字符串被保留。

    tmp = str:split("/", true) 
    log.info("str.split", #tmp, json.encode(tmp))								--日志输出：6	["","tmp","","def","1234",""]

    -- 更多资料
    -- https://wiki.luatos.com/develop/hex_string.html
    -- https://wiki.luatos.com/_static/lua53doc/manual.html#3.4
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
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
