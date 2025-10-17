-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "zbuffdemo"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- 引入必要的库文件(lua编写), 内部库不需要require
sys = require("sys")

sys.taskInit(function()
    sys.wait(3000)
    -- zbuff可以理解为char[], char*, uint8_t*
    -- 为了与lua更好的融合, zbuff带长度,带指针位置,可动态扩容
    local buff = zbuff.create(1024)
    -- 可当成数组直接赋值和取值
    buff[0] = 0xAE
    log.info("zbuff", "buff[0]", buff[0])

    -- 以io形式操作
    
    -- 写数据write, 操作之后指针会移动,跟文件句柄一样
    buff:write("123") -- 字符串
    buff:write(0x12, 0x13, 0x13, 0x33) -- 直接写数值也可以
    
    -- 设置指针位置, seek
    buff:seek(5, zbuff.SEEK_CUR) -- 指针位置+5
    buff:seek(0)                 -- 绝对地址

    -- 读数据read, 指针也会移动
    local data = buff:read(3)
    log.info("zbuff", "data", data)

    -- 清除全部数据,但指针位置不变
    buff:clear() -- 默认填0
    buff:clear(0xA5) -- 也可以指定填充的内容

    -- 支持以pack库的形式写入或读取数据
    buff:seek(0)
    buff:pack(">IIHA", 0x1234, 0x4567, 0x12,"abcdefg")
    buff:seek(0)
    local cnt,a,b,c,s = buff:unpack(">IIHA10")

    -- 也可以直接按类型读写数据
    local len = buff:writeI8(10)
    local len = buff:writeU32(1024)
    local i8data = buff:readI8()
    local u32data = buff:readU32()

    -- 取出指定区间的数据
    local fz = buff:toStr(0,5)

    -- 获取其长度
    log.info("zbuff", "len", buff:len())
    -- 获取其指针位置
    log.info("zbuff", "len", buff:used())

    -- 测试writeF32, 注意, EC618系列(Air780E等), V1106会死机, 在V1107修复
    buff:seek(0, zbuff.SEEK_SET)
    buff:writeF32(1.2)
    buff:seek(0, zbuff.SEEK_SET)
    log.info("buff", "rw", "f32", buff:readF32())

    -- 更多用法请查阅api文档

    log.info("zbuff", "demo done")
end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
