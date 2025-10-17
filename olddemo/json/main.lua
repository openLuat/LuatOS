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
        log.info("json", jdata)

        -- 字符串转table
        local str = "{\"abc\":1234545}" -- 字符串可以来源于任何地方,网络,文本,用户输入,都可以
        local t = json.decode(str)
        if t then -- 若解码失败, 会返回nil
            log.info("json", "decode", t.abc)
        end

        -- lua中的table是 数组和hashmap的混合体
        -- 这对json来说会有一些困扰, 尤其是空的table
        local t = {abc={}}
        -- 假设从业务上需要输出 {"abc":[]}
        -- 实际会输出 {"abc": {}} , 空table是优先输出 hashmap 形式, 而非数组形式
        log.info("json", "encode", json.encode(t))
        -- 混合场景, json场景应避免使用
        t.abc.def = "123"
        t.abc[1] = 345
        -- 输出的内容是 {"abc":{"1":345,"def":"123"}}
        log.info("json", "encode2", json.encode(t))

        -- 浮点数演示
        -- 默认%.7g
        log.info("json", json.encode({abc=1234.300}))
        -- 限制小数点到1位
        log.info("json", json.encode({abc=1234.300}, "1f"))

        -- 2023.6.8 处理\n在encode之后变成\b的问题
        local tmp = "ABC\r\nDEF\r\n"
        local tmp2 = json.encode({str=tmp})
        log.info("json", tmp2)
        local tmp3 = json.decode(tmp2)
        log.info("json", "tmp3", tmp3.str, tmp3.str == tmp)
        -- break

        log.info("json.null", json.encode({name=json.null}))
        log.info("json.null", json.decode("{\"abc\":null}").abc == json.null)
        log.info("json.null", json.decode("{\"abc\":null}").abc == nil)

        -- 测试浮点数的解码和编码
        local tmp = "{\"abc\":3.5}"
        local abc, err = json.decode(tmp)
        log.info("json浮点数测试", abc, err, abc.abc, abc.abc == 3.5)
        log.info("json浮点数测试", json.encode({abc=3.5}, "1f"))
        log.info("json浮点数测试", json.encode(abc, "1f"))
        log.info("json浮点数测试", string.format("%1f", abc.abc))
        log.info("json浮点数测试", string.format("%7g", abc.abc))
        -- log.info("json浮点数测试", string.format("%d", abc.abc))
        local tmp = abc.abc
        local tmp3 = 3.5
        local tmp2 = tostring(tmp)
        log.info("json浮点数测试", abc, err, abc.abc, tmp, tmp2, tostring(tmp3))

        -- 以下代码仅64bit固件可正确运行
        local tmp = [[{ "timestamp": 1691998307973}]]
        local abc, err = json.decode(tmp)
        log.info("json", abc, err)
        log.info("json", abc and abc.timestamp)

        break
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
