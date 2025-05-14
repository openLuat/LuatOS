
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "bit64_test"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- 引入必要的库文件(lua编写), 内部库不需要require
sys = require("sys")

if rtos.bsp() == "EC618" and pm and pm.PWK_MODE then
    pm.power(pm.PWK_MODE, false)
end


if wdt then
    --添加硬狗防止程序卡死，在支持的设备上启用这个功能
    wdt.init(9000)--初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000)--3s喂一次狗
end


local data,b64,b32,a,b
if bit64 then
	log.style(1)

-- 2.1 将数据进行 32 位和 64 位互转
    log.info("bit64 演示")
    log.info("-- 2.1")
    data = 12345678
    -- 32bit数据转成64bit数据
    b64 = bit64.to64(data)
    -- 64bit数据转成32bit输出
    b32 = bit64.to32(b64)
    log.info("i32", b32, mcu.x32(b32))
    data = -12345678
    b64 = bit64.to64(data)
    b32 = bit64.to32(b64)
    log.info("i32", b32, mcu.x32(b32))
    data = 12.34234
    b64 = bit64.to64(data)
    b32 = bit64.to32(b64)
    log.info("f32", data, b32)
    data = -12.34234
    b64 = bit64.to64(data)
    b32 = bit64.to32(b64)
    log.info("f32", data, b32)

-- 2.2 64 位数据之间进行运算
    log.info("-- 2.2")
    a = bit64.to64(87654321)
    b = bit64.to64(12345678)
    -- 64bit数据格式化打印成字符串，用于显示值。64bit数据加,a+b,a和b中有一个为浮点，则按照浮点运算
    -- 64bit数据加,a+b,a和b中有一个为浮点，则按照浮点运算
    log.info("87654321+12345678=", bit64.show(bit64.plus(a,b)))
    -- 64bit数据减,a-b,a和b中有一个为浮点，则按照浮点运算
    log.info("87654321-12345678=", bit64.show(bit64.minus(a,b)))
    -- 64bit数据乘,a*b,a和b中有一个为浮点，则按照浮点运算
    log.info("87654321*12345678=", bit64.show(bit64.multi(a,b)))
    -- 64bit数据除,a/b,a和b中有一个为浮点，则按照浮点运算
    log.info("87654321/12345678=", bit64.show(bit64.pide(a,b)))

-- 2.3 64 位与 32 位数据之间进行运算
    log.info("-- 2.3")
    a = bit64.to64(87654321)
    b = bit64.to64(12345678)
    -- 64bit数据格式化打印成字符串，用于显示值。64bit数据加,a+b,a和b中有一个为浮点，则按照浮点运算
    -- 64bit数据加,a+b,a和b中有一个为浮点，则按照浮点运算
    log.info("87654321+12345678=", bit64.show(bit64.plus(a,b)))
    -- 64bit数据减,a-b,a和b中有一个为浮点，则按照浮点运算
    log.info("87654321-12345678=", bit64.show(bit64.minus(a,b)))
    -- 64bit数据乘,a*b,a和b中有一个为浮点，则按照浮点运算
    log.info("87654321*12345678=", bit64.show(bit64.multi(a,b)))
    -- 64bit数据除,a/b,a和b中有一个为浮点，则按照浮点运算
    log.info("87654321/12345678=", bit64.show(bit64.pide(a,b)))

-- 2.4 64 位数据之间，一个数是浮点数进行运算
    log.info("-- 2.4")
    a = bit64.to64(87654.326)
    b = bit64.to64(12345)
    --进行四则运算
    log.info("87654.326+12345=", 87654.326 + 12345)
    log.info("87654.326+12345=", bit64.show(bit64.plus(a,b)))
    log.info("87654.326-12345=", bit64.show(bit64.minus(a,b)))
    log.info("87654.326*12345=", bit64.show(bit64.multi(a,b)))
    log.info("87654.326/12345=", bit64.show(bit64.pide(a,b)))

-- 2.5 64 位浮点数计算
    log.info("-- 2.5")
    a = bit64.to64(87654.32)
    b = bit64.to64(12345.67)
    --
    log.info("float", "87654.32+12345.67=", 87654.32 + 12345.67)
    log.info("double","87654.32+12345.67=", bit64.show(bit64.plus(a,b)))
    log.info("double to float","87654.32+12345.67=", bit64.to32(bit64.plus(a,b)))
    log.info("87654.32-12345.67=", bit64.show(bit64.minus(a,b)))
    log.info("87654.32*12345.67=", bit64.show(bit64.multi(a,b)))
    log.info("87654.32/12345.67=", bit64.show(bit64.pide(a,b)))
    log.info("double to int64", "87654.32/12345.67=", bit64.show(bit64.pide(a,b,nil,true)))

-- 2.6 浮点数之间的运算
    log.info("-- 2.6")
	a = bit64.to64(87654.32)
    b = bit64.to64(12345.67)
    log.info("float", "87654.32+12345.67=", 87654.32 + 12345.67)
    log.info("double","87654.32+12345.67=", bit64.show(bit64.plus(a,b)))
    log.info("double to float","87654.32+12345.67=", bit64.to32(bit64.plus(a,b)))
    log.info("87654.32-12345.67=", bit64.show(bit64.minus(a,b)))
    log.info("87654.32*12345.67=", bit64.show(bit64.multi(a,b)))
    log.info("87654.32/12345.67=", bit64.show(bit64.pide(a,b)))
    log.info("double to int64", "87654.32/12345.67=", bit64.show(bit64.pide(a,b,nil,true)))

-- 2.7 64 位数据移位操作
    log.info("-- 2.7")
    a = bit64.to64(0xc0000000)
    b = 2
-- 64bit数据位移 a>>b 或者 a<<b
    a = bit64.shift(a,8,true)
    log.info("0xc0000000 << 8 =", bit64.show(a, 16))
    log.info("0xc000000000+2=", bit64.show(bit64.plus(a,b), 16))
    log.info("0xc000000000-2=", bit64.show(bit64.minus(a,b), 16))
    log.info("0xc000000000*2=", bit64.show(bit64.multi(a,b), 16))
    log.info("0xc000000000/2=", bit64.show(bit64.pide(a,b), 16))

-- 2.8  将字符串转为 LongLong 数据
    log.info("-- 2.8")
    if bit64.strtoll then
        -- 将字符串转为LongLong数据
        local data = bit64.strtoll("864040064024194", 10)
        log.info("data", data:toHex())
        log.info("data", bit64.show(data))
    end
end
-- 2.9  获取高精度 tick，输出转换好的 64 位结构
log.info("-- 2.9")
local function sys_run_time()
    -- 获取启动后的高精度tick，如果支持bit64库，可以直接输出转换好的bit64结构
    local tick64, per = mcu.tick64(true)
    local per_cnt = per * 1000000
    while true do
        tick64, per = mcu.tick64(true)

        log.info("work time","当前时间", bit64.to32(bit64.pide(tick64,per_cnt)))
        sys.wait(1000)
    end
end


if mcu.tick64 then
	sys.taskInit(sys_run_time)
end

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!