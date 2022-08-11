
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "miniz"
VERSION = "1.0.0"

-- 引入必要的库文件(lua编写), 内部库不需要require
local sys = require "sys"

log.info("main", "hello world")

print(_VERSION)

sys.taskInit(function()
    local bigdata = "1221341252345234634564576"
    for i=10,1,-1 do
        bigdata = bigdata .. tostring(i) .. bigdata
    end

    local cdata = miniz.compress(bigdata) 
    -- lua 的 字符串相当于有长度的char[],可存放包括0x00的一切数据
    assert(cdata, "compress fail!!")
    if cdata then
        -- 检查压缩前后的数据大小
        log.info("miniz", "before", #bigdata, "after", #cdata)
        log.info("miniz", "cdata as hex", cdata:toHex())
    
        -- 解压, 得到原文
        local udata = miniz.compress(cdata)
        --log.info("miniz", "udata", udata)
        assert(udata == bigdata, "compress data NOT match")
    end

    os.exit()
end)



-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
