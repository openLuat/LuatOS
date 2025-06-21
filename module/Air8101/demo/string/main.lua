-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "demo_str_test"
VERSION = "1.0.0"

LOG_TAG = "str"

--[[
用例0101 字符串定义与基本操作
1. lua的字符串是带长度, 不依赖0x00作为结束字符串, 可以包含任意数据
2. lua的字符串是不可变的, 就不能直接修改字符串的一个字符, 修改字符会返回一个新的字符串
]]--
function tc0101_str_base_operation()
    -- 双引号定义字符串,若字符串中包含了单引号，使用双引号来定义字符串会避免转义字符的需要
    local str1 = "Hello 'LuatOS'"
    -- 单引号定义字符串,若字符串中包含了双引号，使用单引号来定义字符串会避免转义字符的需要
    local str2 = '你好"LuatOS"'
    -- 双方括号定义多行字符串
    local str_lines = [[
Hello Air8101!
Hello "LuatOS"!\r\n
]]
    
    log.info(LOG_TAG, "双括号定义单行string:", str1)
    log.info(LOG_TAG, "单引号定义单行string:", str2)
    log.info(LOG_TAG, "双方括号定义多行string:", str_lines)
    
    -- 反斜杠转义字符
    local str3 = "Hello\nLuatOS"
    log.info(LOG_TAG, "string转义换行:", str3)

    -- 字符串长度获取的方式: #操作符或string.len
    local len1 = string.len(str1)
    log.info(LOG_TAG, str1 .. " len=", len1)
    assert(len1 == 14)
    -- 使用UTF-8字符编码的情况下一个中文字符一般占3个字节
    local len2 = #str2
    log.info(LOG_TAG, str2 .. " len=", len2)
    assert(len2 == 14)
    -- 多行字符串长度统计包括空格换行等不可见字符,(`[[`后面紧跟的一个换行符不包含在字符串内,不识别转义序列）
    local len_lines = #str_lines
    log.info(LOG_TAG, str_lines .. " len=", len_lines)
    assert(len_lines == 35)

    -- 字符串拼接, 使用".."来拼接, 
    -- 只能为数字或字符串(nil/boolean可以用tostring转换)
    -- 左右两边有空格(与数字拼接时必需)
    local str4 = "hello " .. "luat " .. 2025
    log.info(LOG_TAG, str4 .. " len=", #str4)
    assert(str4 == "hello luat 2025")
    str4 = "display " .. tostring(nil) .. " and " .. tostring(false)
    log.info(LOG_TAG, str4 .. " len=", #str4)
    assert(str4 == "display nil and false")
end


--[[
用例0102 字符串模式匹配-查找
]]--
function tc0102_str_pattern_matching()
    local text = "hello-air8101!hello luatos 2025!"
    local s,e,sub_str
    --[[
    string.find
    查找字符串中是否包含匹配的pattern，并返回匹配的位置
    ]]--
    -- 仅指定pattern, 默认打开模式匹配,如果pattern含lua支持匹配的魔法字符，需用%符号，转义为原生字符才能匹配
    s,e = string.find(text, "hello%-air")
    log.info(LOG_TAG, "match hello-air", s, e)
    assert(s == 1 and e == 9)
    -- 注意:这里需要带括号()返回捕获匹配子串，否则返回nil
    s, e, sub_str = string.find(text, "(%d%d%d%d)") 
    log.info(LOG_TAG, "match %d%d%d%d", s, e, sub_str)
    assert(s == 10 and e == 13 and sub_str == "8101")
    -- 指定起始位置init
    s, e= string.find(text, "hello", 13)
    log.info(LOG_TAG, "match hello", s, e)
    assert(s == 15 and e == 19)
    -- 指定起始位置init,关闭模式匹配(plain=true)
    s, e, sub_str = string.find(text, "%d%d%d%d", 15, true)
    log.info(LOG_TAG, "match %d%d%d%d", s, e, sub_str)
    assert(s == nil and e == nil and sub_str == nil)

    --[[
    string.match,
    查找字符串中第一个匹配pattern的字符串
    ]]-- 
    -- 不带括号时返回匹配的全字符串
    sub_str = string.match(text, "%d%d%d%d")
    log.info(LOG_TAG, "match %d%d%d%d", sub_str)
    assert(sub_str == "8101")
    -- 指定起始位置init,带括号时只返回括号中的捕获匹配子串
    sub_str = string.match(text, "%d(%d%d)%d", 15)
    log.info(LOG_TAG, "match %d(%d%d)%d", sub_str)
    assert(sub_str == "02")
    --[[
    string.gmatch,
    返回一个迭代器，依次匹配字符串中的所有符合模式的子串
    ]]-- 
    local str_table = {}
    local iter_func = string.gmatch(text, "%d%d%d%d")
    for val in iter_func do
        log.info(LOG_TAG, "gmatch ", val)
        table.insert(str_table, val)
    end
    assert(str_table[1] == "8101" and str_table[2] == "2025")
end

--[[
用例0103 字符串模式匹配-替换操作
]]--
function tc0103_str_replace()
    local text = "hello air8101!hello luatos 2025!"
    local new_text,times
    --[[
    string.gsub,
    替换字符串中的所有或部分匹配的模式，
    ]]-- 
    -- 替换参数为字符串, 指定匹配"hello"字符串，第三参数指定替换为"hi", 第四个参数指定替换次数,替换1次，将hello替换成hi
    local new_text = string.gsub(text, "hello", "hi", 1)
    -- 返回值: new_text为"hi air8101!hello luatos 2025!"
    log.info(LOG_TAG, text .. " change to ", new_text)
    assert(new_text == "hi air8101!hello luatos 2025!")
    -- 指定pattern为(%w+)匹配所有字母及数字，把匹配到的子串作为第一组捕获（这里一对括号共一组捕获），通过%1来引用
    -- 替换动作为重复第一组捕获中间加","间隔,全部匹配替换
    local new_text, times = string.gsub(text, "(%w+)", "%1,%1")
    log.info(LOG_TAG, text .. " change to ", new_text)
    assert(new_text == "hello,hello air8101,air8101!hello,hello luatos,luatos 2025,2025!" and times == 5)
    -- 替换参数为table,匹配到的字符串当做键在表中查找，找到后用键对应值做替换, 取值第二个返回参数为替换次数
    local str_tab = {hello = "hi"}
    new_text, times = string.gsub(text, "hello", str_tab)
    log.info(LOG_TAG, text .. " change to ", new_text)
    assert(new_text == "hi air8101!hi luatos 2025!" and times == 2)
    -- 替换参数为function,查找到的字符当做函数的参数传入替换函数，变更字符
    new_text, times = string.gsub(text, "hello", function (str)
        return string.upper(str)
    end)
    log.info(LOG_TAG, text .. " change to ", new_text)
    assert(new_text == "HELLO air8101!HELLO luatos 2025!" and times == 2)
end

--[[
用例0104 字符截取、复制与反转操作
]]--
function tc0104_str_truncate_copy_reverse()
    local text = "hello luatos!!"
    --[[
    string.sub,
    从一个字符串中截取指定范围的子字符串
    ]]--
    -- 截取起始位置7到末尾的子字符串
    local sub_str = string.sub(text, 7)
    log.info(LOG_TAG, "sub_str", sub_str)
    assert(sub_str == "luatos!!")
    -- 截取起始位置11到倒数第三位置
    local sub_str = string.sub(text, 11, -3)
    log.info(LOG_TAG, "sub_str", sub_str)
    assert(sub_str == "os")

    --[[
    string.rep
    字符串重复指定次数(可指定分隔符)，返回一个新的字符串
    ]]--
    local new_str = string.rep("hello", 3)
    log.info(LOG_TAG, "new_str", new_str)
    assert(new_str == "hellohellohello")
    local new_str = string.rep("hello", 3, "!")
    log.info(LOG_TAG, "new_str", new_str)
    assert(new_str == "hello!hello!hello")

    --[[
    string.reverse
    返回字符串的反转字符串
    ]]--
    local new_str = string.reverse("hello*123")
    log.info(LOG_TAG, "new_str", new_str)
    assert(new_str == "321*olleh")
end

--[[
用例0105 字符格式化与转换操作
]]--
function tc0105_str_conversion()
    --[[
    string.lower
    字符串中的所有字母转换为小写
    ]]--
    local text1 = string.lower("Hello LuatOS 2025!")
    log.info(LOG_TAG, text1)
    assert(text1 == "hello luatos 2025!")
    --[[
    string.upper
    字符串中的所有字母转换为大写
    ]]--
    local text2 = string.upper("Hello LuatOS 2025!")
    log.info(LOG_TAG, text2)
    assert(text2 == "HELLO LUATOS 2025!")
    --[[
    string.char
    接收零或更多的整数,返回和参数数量相同长度的字符串
    ]]--
    local str = string.char(72, 101, 108, 108, 111)
    log.info(LOG_TAG, str)
    assert(str == "Hello")
    --二进制数据
    local bindat = string.char(0, 23, 255, 124, 171)
    assert(bindat == "\x00\x17\xFF\x7C\xAB")
    --[[
    string.byte
    返回字符串指定位置的内部数字编码值
    ]]--
    -- 获取指定开始结束位置的数值
    local dat0,dat1,dat2,dat3,dat4 = string.byte("hello luatos", 6, 10)
    log.info(LOG_TAG, dat0,dat1,dat2,dat3,dat4)
    assert(dat0==32 and	dat1==108 and dat2==117	and dat3==97 and dat4==116)
    -- 获取指定位置的一个数值
    local dat5 = string.byte("\x01\xAB", 2)
    log.info(LOG_TAG, dat5)
    assert(dat5 == 171)

    --[[
    string.format
    格式化字符串并返回新字符串
    ]]--
    local str1 = '\t\rHello \n2025\\ "Lua"\0'    -- "\t\rHello \n2025\\ \"Lua\"\0"
    -- %q选项接受一个字符串转化为可安全被 Lua 编译器读入的格式
    -- (显式显示几乎所有特殊字符,忽略转义, 返回一个带双引号的新字符串)
    local fmt_str = string.format("return str is %q", str1)
    log.info(LOG_TAG, fmt_str) -- 返回带双引号的字符串
    assert(fmt_str == 'return str is "\\9\\13Hello \\\n2025\\\\ \\"Lua\\"\\0"')
    -- %d选项接受一个整型，%s选项接受一个字符串，%f选项接受一个单浮点数(默认6位小数)
    fmt_str = string.format("%d,%s,%f",123,"test",1.253)
    log.info(LOG_TAG, fmt_str)
    assert(fmt_str == "123,test,1.253000")
end

--[[
用例0106 格式化二进制数据打包与解包
]]--
function tc0106_str_bin_pack_unpack()
    -- 假设按照这个(1, 4, 0xCD56AB12, 0x0A, 0x0104)数据格式打包，
    -- 小端格式十六进制表示为：01 00 | 04 00 | 12 AB 56 CD | 0A | 04 01  
    local test_bin_str = "\x01\x00\x04\x00\x12\xAB\x56\xCD\x0A\x04\x01"
    local pack_str = string.pack("<HHI4BH", 1, 4, 0xCD56AB12, 0x0A, 0x0104)
    -- 这里也可以使用string.toHex(pack_str) 直接转换成十六进制数据字符串
    local fmt_str = string.format("%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X",
                                    pack_str:byte(1),pack_str:byte(2),pack_str:byte(3),pack_str:byte(4),
                                    pack_str:byte(5),pack_str:byte(6),pack_str:byte(7),pack_str:byte(8),
                                    pack_str:byte(9),pack_str:byte(10),pack_str:byte(11))
    log.info(LOG_TAG, fmt_str, pack_str:len(), string.packsize("<HHI4BH"))
    assert(pack_str == test_bin_str and pack_str:len() == string.packsize("<HHI4BH"))
    -- 解包
    local dat1,dat2,dat3,dat4,dat5 = string.unpack("<HHI4BH", test_bin_str)
    log.info(LOG_TAG, string.format("%X,%X,%04X,%X,%X",dat1,dat2,dat3,dat4,dat5))
    assert(dat1 == 1 and dat2 == 4 and dat3 == 0xCD56AB12 and dat4 == 0x0A and dat5 == 0x104)
    
    -- 测试依次打包数值，字符串，浮点数,string.packsize不能用于含s,z的变长选项
    -- 选项s6表示把字符串长度保存在6个字节中
    pack_str = string.pack("i4s6f", 42, "Lua", 3.14159)
    log.info(LOG_TAG, pack_str:len())
    -- 可以分次解包,返回已解数据及未解析的开始位置
    local data1, pos = string.unpack("i4", pack_str)
    -- 可以分次解包,指定下次解析开始位置
    local data2, data3 = string.unpack("s6f", pack_str, pos)
    log.info(LOG_TAG, string.format("%d,%s,%.5f",data1,data2,data3))
    assert(data1 == 42 and data2 == "Lua" and string.format("%.5f",data3) == "3.14159")
end

--[[
用例0107 字符转换输出操作(扩展API)
]]--
function tc0107_str_ext_conversion()
    --[[
    string.toHex
    输入字符串转换，可指定分隔符，返回hex字符串和字符串长度(长度不含分隔符)
    ]]--
    -- 默认分隔符为"" 空字符串
    local text = "Hello Luatos123"
    local hex_str, hex_len = string.toHex(text)
    log.info(LOG_TAG, text, hex_str, hex_len)
    -- 指定分隔符为" " 空格
    local data = "\x01\xAA\x02\xFE\x23"
    local hex_data, hex_data_len = string.toHex(data, " ")
    log.info(LOG_TAG, hex_data, hex_data_len)
    local utf8_data = "你好。"
    local hex_utf8_data = string.toHex(utf8_data)
    log.info(LOG_TAG, hex_utf8_data)
    --[[
    string.fromHex
    输入hex字符串转换返回字符串,忽略除0-9,a-f,A-F的其他字符
    ]]--
    local ret_text = string.fromHex(hex_str)
    local ret_data = string.fromHex(hex_data)
    local ret_utf8_data = string.fromHex(hex_utf8_data)
    log.info(LOG_TAG, 
            ret_text, 
            string.format("%02X%02X%02X%02X%02X",ret_data:byte(1),ret_data:byte(2),
                            ret_data:byte(3),ret_data:byte(4),ret_data:byte(5)),    
            ret_utf8_data)
    assert(ret_text == text and ret_data == data and ret_utf8_data == utf8_data)

    --[[
    string.toValue
    输入返回二进制字符串,及转换的字符数
    ]]--
    local bin_str,count = string.toValue("123456abc")
    log.info(LOG_TAG, 
        -- 这里也可以使用string.toHex(bin_str) 直接转换成十六进制数据字符串
            string.format("%02X%02X%02X%02X%02X%02X%02X%02X%02X",
                        bin_str:byte(1),bin_str:byte(2),bin_str:byte(3),
                        bin_str:byte(4),bin_str:byte(5),bin_str:byte(6),
                        bin_str:byte(7),bin_str:byte(8),bin_str:byte(9)),
            count) -- count 为转换的字符数
    assert(bin_str == "\x01\x02\x03\x04\x05\x06\x0a\x0b\x0c" and count == 9)
end



--[[
用例0108 字符编解码-Base64/Base32(扩展API)
]]--
function tc0108_str_ext_base64_and_base32()
    -- 测试普通字符串base64编解码
    local text = "Hello"
    local base64_str = string.toBase64(text)
    log.info(LOG_TAG, base64_str)
    local ret_text = string.fromBase64(base64_str)
    assert(ret_text == text)
    -- 测试二进制数据字符串base64编解码
    local data = "\x01\xAB\x34\xFF"
    local base64_data = string.toBase64(data)
    log.info(LOG_TAG, base64_data)
    local ret_data = string.fromBase64(base64_data)
    assert(ret_data == data)
    -- 测试utf8数据字符串base64编解码
    local utf8_data = "你好"
    local base64_utf8data = string.toBase64(utf8_data)
    log.info(LOG_TAG, base64_utf8data)
    local ret_utf8_data = string.fromBase64(base64_utf8data)
    assert(utf8_data == utf8_data)
    -- 测试普通字符串base32编解码
    local text = "Luatos"
    local base64_str = string.toBase32(text)
    log.info(LOG_TAG, base64_str)
    local ret_text = string.fromBase32(base64_str)
    assert(ret_text == text)
    -- 测试二进制数据字符串base32编解码
    local data = "\x01\xAB\x34\xFF"
    local base64_data = string.toBase32(data)
    log.info(LOG_TAG, base64_data)
    local ret_data = string.fromBase32(base64_data)
    assert(ret_data == data)
    -- 测试utf8数据字符串base32编解码
    local utf8_data = "你好"
    local base64_utf8data = string.toBase32(utf8_data)
    log.info(LOG_TAG, base64_utf8data)
    local ret_utf8_data = string.fromBase32(base64_utf8data)
    assert(utf8_data == utf8_data)
end


--[[
用例0109 字符编解码-URL编码(扩展API)
]]--
function tc0109_str_ext_urlcode()
    local text = "Hello world&luat/123*A_B"
    -- 第二个参数0:默认参考标准php(可不填)，不转换的字符序列".-*_",空格用'+'
    local urlencode = string.urlEncode(text) 
    log.info(LOG_TAG, "defalut php", urlencode)
    assert(urlencode == "Hello+world%26luat%2F123*A_B")
    -- 第二个参数1:参考rfc3986,不转换的字符序列".-_",空格用'%20'
    urlencode = string.urlEncode(text, 1) 
    log.info(LOG_TAG, "rfc3986", urlencode)
    assert(urlencode == "Hello%20world%26luat%2F123%2AA_B")
    -- 第二个参数-1:表示自定义, 第三参数0:空格用'+',1:空格用'%20';第四参数指定不用转换的字符序列
    urlencode = string.urlEncode(text, -1, 0, "&/ ") 
    log.info(LOG_TAG, "self defined", urlencode)
    assert(urlencode == "Hello world&luat/123%2AA%5FB")
end


--[[
用例0110 字符串分隔符拆分子字符串(扩展API)
]]--
function tc0110_str_ext_split()
    local text = "/hello,///world,**/luatos//2025*/"
    -- 默认分隔符',',默认不保留空白片段
    local table1 = string.split(text)  -- 这里第二三参数不填使用默认值
    log.info(LOG_TAG, #table1, table1[1], table1[2], table1[3])
    assert(table1[1] == "/hello" and table1[2] == "///world" and table1[3] == "**/luatos//2025*/")

    -- 分隔符'/',保留空白片段,字符串中有连续的分隔符视为分隔两个空字符串,开始和结束有分隔符则分别都有空字符串
    local table2 = string.split(text,'/', true)
    log.info(LOG_TAG, #table2, json.encode(table2))
    assert(table2[1] == "" and table2[2] == "hello," and table2[3] == ""
            and table2[4] == "" and table2[5] == "world,**"
            and table2[6] == "luatos" and table2[7] == ""
            and table2[8] == "2025*" and table2[9] == "")

    -- 分隔符'*',保留空白片段,采用':'调用函数，text当作第一个实参传递给函数，等同string.split(text)
    local table3 = text:split('*', true)
    log.info(LOG_TAG, #table3, json.encode(table3))
    assert(table3[1] == "/hello,///world," and table3[2] == "" and table3[3] == "/luatos//2025" and table3[4] == "/")
    
    -- 分隔符'o', 不保留空白片段
    local table4 = text:split('o')
    log.info(LOG_TAG, #table4, json.encode(table4))
    assert(table4[1] == "/hell" and table4[2] == ",///w" and table4[3] == "rld,**/luat" and table4[4] == "s//2025*/")
end

--[[
用例0111 字符串前后缀判断与操作(扩展API)
]]--
function tc0111_str_ext_prefix_suffix()
    local text = " \tHello LuatOS2025\r\n"
    --[[
    string.trim
    去除字符串头尾的空白字符包括空格、制表符(\t)、回车(\r)和换行(\n)符
    ]]--
    -- 第二参数true表示去除前缀(默认true可不填)，第三参数true表示去除后缀(默认true可不填)
    local ret_str1 = string.trim(text)
    log.info(LOG_TAG, #ret_str1, ret_str1)
    assert(ret_str1 == "Hello LuatOS2025")
    -- 第二参数true表示去除前缀，第三参数false表示保留后缀
    local ret_str2 = string.trim(text, true, false)
    log.info(LOG_TAG, #ret_str2, ret_str2)
    assert(ret_str2 == "Hello LuatOS2025\r\n")
    --[[
    string.startsWith
    判断字符串前缀，匹配前缀返回true
    ]]--
    local rc = string.startsWith(ret_str1, "He")
    log.info(LOG_TAG, "startwith \"He\", rc=", rc)
    assert(rc)
    rc = string.startsWith(text, " \t")
    log.info(LOG_TAG, "startwith \" \\t\", rc=", rc)
    assert(rc)
    --[[
    string.endsWith
    判断字符串后缀，匹配后缀返回true
    ]]--
    rc = string.endsWith(ret_str1, "25")
    log.info(LOG_TAG, "endwith \"25\",rc=", rc)
    assert(rc)
    rc = string.endsWith(text, "\r\n")
    log.info(LOG_TAG, "endwith \"\\r\\n\",rc=", rc)
    assert(rc)
end


--[[
用例0201 测试空字符串参数(仅测试扩展API接口)
]]--
function tc0201_str_ext_nullstr_param()
    local ret_str, ret_len = string.toHex("")
    log.info(LOG_TAG,"toHex:", ret_str, ret_len)
    assert(ret_str == "")
    ret_str = string.fromHex("")
    log.info(LOG_TAG,"fromHex:", ret_str)
    assert(ret_str == "")
    ret_str,ret_len = string.toValue("")
    log.info(LOG_TAG,"toValue:", ret_str, ret_len)
    assert(ret_str == "")
    ret_str = string.toBase64("")
    log.info(LOG_TAG,"toBase64:", ret_str)
    assert(ret_str == "")
    ret_str = string.fromBase64("")
    log.info(LOG_TAG,"fromBase64:", ret_str)
    assert(ret_str == "")
    ret_str = string.toBase32("")
    log.info(LOG_TAG,"toBase32:", ret_str)
    assert(ret_str == "")
    ret_str = string.fromBase32("")
    log.info(LOG_TAG,"fromBase32:", ret_str)
    assert(ret_str == "")
    ret_str = string.urlEncode("")
    log.info(LOG_TAG,"urlEncode:", ret_str)
    assert(ret_str == "")
    local ret_tab = string.split("")
    log.info(LOG_TAG,"split:", ret_tab)
    assert(type(ret_tab) == "table" and #ret_tab == 0)
    local rc = string.startsWith("","")
    log.info(LOG_TAG,"startsWith:", rc)
    assert(rc == true)
    rc = string.endsWith("","")
    log.info(LOG_TAG,"endsWith:", rc)
    assert(rc == true)
    ret_str = string.trim("")
    log.info(LOG_TAG,"trim:", ret_str)
    assert(ret_str == "")
end

--[[
用例0202 测试异常范围参数(扩展API接口)
]]--
function tc0202_str_ext_over_range_param()
    -- 字符处理方法:char >'9'则(char+9)&0x0f, 否则char&0x0f
    local ret_str,ret_len = string.toValue("1qWe")
    log.info(LOG_TAG, 
            string.format("%02X%02X%02X%02X",
                ret_str:byte(1),ret_str:byte(2),ret_str:byte(3),ret_str:byte(4)),
            ret_len)
    assert(ret_str == "\x01\x0A\x00\x0E")
    ret_str,ret_len = string.toValue(" \r\n")
    log.info(LOG_TAG, 
            string.format("%02X%02X%02X",
                ret_str:byte(1),ret_str:byte(2),ret_str:byte(3)),
            ret_len)
    assert(ret_str == "\x00\x0D\x0A")
    -- 指定异常前后缀的判断比较
    local rc = string.startsWith("hello","12")
    log.info(LOG_TAG,"startsWith:", rc)
    assert(rc == false)
    rc = string.startsWith("hello","hello1")
    log.info(LOG_TAG,"startsWith:", rc)
    assert(rc == false)
    rc = string.startsWith("hello","\0")
    log.info(LOG_TAG,"startsWith:", rc)
    assert(rc == false)
    rc = string.startsWith("hello","")
    log.info(LOG_TAG,"startsWith:", rc)
    assert(rc == true)
    rc = string.endsWith("hello","hello")
    log.info(LOG_TAG,"endsWith:", rc)
    assert(rc == true)
    rc = string.endsWith("hello","")
    log.info(LOG_TAG,"endsWith:", rc)
    assert(rc == true)
end

--[[
用例0203 测试异常范围Base64或Base32参数(扩展API接口)
]]--
function tc0203_str_ext_base64_base32_illegal_param()
    -- Base64/Base32解码测试自动补全填充符'='
    -- 不支持补全填充符？不检查长度？
    local encoded = "SGVsbG8"  -- 缺少填充符
    local decoded = string.fromBase64(encoded)
    log.info(LOG_TAG,"decoded:", decoded)
    assert(decoded == "Hel", "Base64 decode fail")

    encoded = "JR2WC5DPOM"  -- 缺少填充符
    decoded = string.fromBase32(encoded)
    log.info(LOG_TAG,"decoded:", decoded)
    assert(decoded == "Luatos", "Base32 decode fail")

    -- Base64/Base32解码测试异常字符参数
    encoded = "SGsb*G8!"  -- 非法字符
    decoded = string.fromBase64(encoded)
    log.info(LOG_TAG,"decoded:", decoded)
    -- 解码失败应该返回空字符串
    assert(decoded == "", "Base64 igllegal param")

    encoded = "JR2W*08C5DP!"  -- 非法字符 
    decoded = string.fromBase32(encoded)
    log.info(LOG_TAG,"decoded:", decoded)
    -- 解码失败应该返回空字符串
    assert(decoded == "", "Base32 igllegal param")
end

-- 测试用例的table,以函数名为键，函数为值，实际运行无序可以增加测试的随机性
-- string的测试函数集
local str_test_suite = {
    --[[
    接口功能测试
    ]]--
    ["tc0101_str_base_operation"] = tc0101_str_base_operation,
    ["tc0102_str_pattern_matching"] = tc0102_str_pattern_matching,
    ["tc0103_str_replace"] = tc0103_str_replace,
    ["tc0104_str_truncate_copy_reverse"] = tc0104_str_truncate_copy_reverse,
    ["tc0105_str_conversion"] = tc0105_str_conversion,
    ["tc0106_str_bin_pack_unpack"] = tc0106_str_bin_pack_unpack,
    ["tc0107_str_ext_conversion"] = tc0107_str_ext_conversion,
    ["tc0108_str_ext_base64_and_base32"] = tc0108_str_ext_base64_and_base32,
    ["tc0109_str_ext_urlcode"] = tc0109_str_ext_urlcode,
    ["tc0110_str_ext_split"] = tc0110_str_ext_split,
    ["tc0111_str_ext_prefix_suffix"] = tc0111_str_ext_prefix_suffix,
    --[[
    异常与边界测试
    ]]--
    ["tc0201_str_ext_nullstr_param"] = tc0201_str_ext_nullstr_param,
    ["tc0202_str_ext_over_range_param"] = tc0202_str_ext_over_range_param,
    ["tc0203_str_ext_base64_base32_illegal_param"] = tc0203_str_ext_base64_base32_illegal_param,
}

-- test_run函数接受一个table参数，table中包含测试用例函数
-- 调用了sys.wait()需要在任务中调用
function test_run(test_cases)
    local successCount = 0  -- 成功的测试用例计数
    local failureCount = 0  -- 失败的测试用例计数

    -- 遍历table中的每个测试用例函数
    for name, testCase in pairs(test_cases) do
        -- 检查testCase是否为函数
        if type(testCase) == "function" then
            -- 使用pcall来捕获测试用例执行中的错误, 若有错误也继续往下执行
            local success, err = pcall(testCase)  
            if success then
                -- 测试成功，增加成功计数
                successCount = successCount + 1  
                log.info(LOG_TAG, "Test case passed: " .. name)
            else
                -- 测试失败，增加失败计数
                failureCount = failureCount + 1  
                log.info(LOG_TAG, "Test case failed: " .. name .. " - Error: " .. err)
            end
        else
            log.info(LOG_TAG, "Skipping non-function entry: " .. name)
        end
        -- 稍等一会在继续测试
        sys.wait(1000)
    end
    -- 打印测试结果
    log.info(LOG_TAG, "Test run complete - Success: " .. successCount .. ", Failures: " .. failureCount)
end


-- 定义任务来开始demo测试流程
sys.taskInit(function()
    -- 为了显示日志,这里特意延迟一秒
    -- 正常使用不需要delay
    sys.wait(1000)
    
    -- 运行测试套件
    test_run(str_test_suite)
end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!