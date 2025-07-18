-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "jsondemo"
VERSION = "1.0.0"

-- 引入必要的库文件(lua编写), 内部库不需要require
sys = require("sys")

log.info("main", PROJECT, VERSION)

-- json库支持将 table 转为 字符串, 或者反过来, 字符串 转 table
-- 若转换失败, 会返回nil值, 强烈建议在使用时添加额外的判断
sys.taskInit(function()
    while 1 do
        sys.wait(1000)
        -- table 转为 字符串
        local t = {abc=123, def="123", ttt=true}
        local jdata = json.encode(t)
        log.info("json", jdata)  									--日志输出：{"ttt":true,"def":"123","abc":123}

        -- 字符串转table
        local str = "{\"abc\":1234545}" -- 字符串可以来源于任何地方,网络,文本,用户输入,都可以
        local t = json.decode(str)
        if t then
			-- 若解码成功，t不为nil
			log.info("json", "decode", t.abc) 						--日志输出：decode	1234545
		else
			-- 若解码失败，t为nil
			log.info("json", "decode failed")
		end

        -- lua中的table是 数组和hashmap的混合体
        -- 这对json来说会有一些困扰, 尤其是空的table
        local t = {abc={}}
        -- 假设从业务上需要输出 {"abc":[]}
        -- 实际会输出 {"abc": {}} , 空table是优先输出 hashmap （即字典模式）形式, 而非数组形式，Lua语言中数组优先级低于hashmap优先级
        log.info("json", "encode", json.encode(t)) 					--日志输出：encode	{"abc":{}}
        -- 混合场景, json场景应避免使用
        t.abc.def = "123"
        t.abc[1] = 345
        -- 输出的内容是 {"abc":{"1":345,"def":"123"}}
        log.info("json", "encode2", json.encode(t))  				--日志输出：encode2	{"abc":{"1":345,"def":"123"}}

        -- 浮点数演示
        log.info("json", json.encode({abc=1234.300}))  				--日志输出：{"abc":1234.300}
        -- 限制小数点到1位
        log.info("json", json.encode({abc=1234.300}, "1f")) 		--日志输出：{"abc":1234.3}

 
        local tmp = "ABC\r\nDEF\r\n"
        local tmp2 = json.encode({str=tmp}) --在JSON中，\r\n 被保留为字符串的一部分
        log.info("json", tmp2)                                    	--日志输出：{"str":"ABC\r\nDEF\r\n"}
        local tmp3 = json.decode(tmp2)								
        log.info("json", "tmp3", tmp3.str, tmp3.str == tmp)			--日志输出：tmp3	ABC
																		--DEF
																		--		true  注：true前存在一个TAB长度（这个TAB原因未知，但不影响使用）
        -- break

        log.info("json.null", json.encode({name=json.null}))		--日志输出：{}  为空对象
        log.info("json.null", json.decode("{\"abc\":null}").abc == json.null)  	--日志输出：false    在 Lua 中，nil 是一种特殊类型，用于表示“无值”或“未定义”。它与任何其他值（包括自定义的 json.null）都不相等
        log.info("json.null", json.decode("{\"abc\":null}").abc == nil)			 --日志输出：false

    end
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
