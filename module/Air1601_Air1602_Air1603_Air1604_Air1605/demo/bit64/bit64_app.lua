--[[
@module  bit64_app
@summary bit64_app应用功能模块 
@version 1.0
@date    2025.10.14
@author  沈园园
@usage
本文件为bit64应用功能模块，核心业务逻辑为：
1、演示在 32 位系统上对 64 位数据的基本算术运算和逻辑运算；

本文件没有对外接口，直接在main.lua中require "bit64_app"就可以加载运行；
]]

--定义几个变量
local data,b64,b32,a,b

--设置调试风格1: I/main.lua:12 ABC DEF 123（在开头添加文件位置信息）
log.style(1)

--本文的64bit数据为：小端格式的9字节数据的字符串，最后一个字节是类型（0是整数，1是浮点）, 前面8个字节是数据。
--十进制转123456对应64bit十六进制字符串"40E2010000000000"

if bit64 then
	log.info("bit64 演示")
    
    --将数据进行 32 位和 64 位互转
    --123456对应64bit的9字节数据HEX字符
    data = "40E201000000000000"
    --需将HEX字符串转成Lua字符串填入 
    b32 = bit64.to32(data:fromHex())
    log.info("i32", b32, mcu.x32(b32))    
    
    data = 12345678
	b64 = bit64.to64(data)
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

    --64 位数据之间进行运算
    --64bit数据格式化打印成字符串，用于显示值
    --64bit数据加,a+b,a和b中有一个为浮点，则按照浮点运算
    --64bit数据减,a-b,a和b中有一个为浮点，则按照浮点运算
    --64bit数据乘,a*b,a和b中有一个为浮点，则按照浮点运算
    --64bit数据除,a/b,a和b中有一个为浮点，则按照浮点运算
	a = bit64.to64(87654321)
	b = bit64.to64(12345678)
	log.info("87654321+12345678=", bit64.show(bit64.plus(a,b)))
	log.info("87654321-12345678=", bit64.show(bit64.minus(a,b)))
	log.info("87654321*12345678=", bit64.show(bit64.multi(a,b)))
	log.info("87654321/12345678=", bit64.show(bit64.pide(a,b)))

	--64 位与 32 位数据之间进行运算
    a = bit64.to64(87654321)
	b = 1234567
	log.info("87654321+1234567=", bit64.show(bit64.plus(a,b)))
	log.info("87654321-1234567=", bit64.show(bit64.minus(a,b)))
	log.info("87654321*1234567=", bit64.show(bit64.multi(a,b)))
	log.info("87654321/1234567=", bit64.show(bit64.pide(a,b)))


	--64 位数据之间，一个数是浮点数进行运算
    a = bit64.to64(87654.326)
	b = bit64.to64(12345)
	log.info("87654.326+12345=", 87654.326 + 12345)
	log.info("87654.326+12345=", bit64.show(bit64.plus(a,b)))
	log.info("87654.326-12345=", bit64.show(bit64.minus(a,b)))
	log.info("87654.326*12345=", bit64.show(bit64.multi(a,b)))
	log.info("87654.326/12345=", bit64.show(bit64.pide(a,b)))

	--64 位浮点数计算
    a = bit64.to64(87654.32)
	b = bit64.to64(12345.67)
	log.info("float", "87654.32+12345.67=", 87654.32 + 12345.67)
	log.info("double","87654.32+12345.67=", bit64.show(bit64.plus(a,b)))
	log.info("double to float","87654.32+12345.67=", bit64.to32(bit64.plus(a,b)))
	log.info("87654.32-12345.67=", bit64.show(bit64.minus(a,b)))
	log.info("87654.32*12345.67=", bit64.show(bit64.multi(a,b)))
	log.info("87654.32/12345.67=", bit64.show(bit64.pide(a,b)))
	log.info("double to int64", "87654.32/12345.67=", bit64.show(bit64.pide(a,b,nil,true)))

	--64 位数据移位操作
    a = bit64.to64(0xc0000000)
	b = 2
	a = bit64.shift(a,8,true)
	log.info("0xc0000000 << 8 =", bit64.show(a, 16))
	log.info("0xc000000000+2=", bit64.show(bit64.plus(a,b), 16))
	log.info("0xc000000000-2=", bit64.show(bit64.minus(a,b), 16))
	log.info("0xc000000000*2=", bit64.show(bit64.multi(a,b), 16))
	log.info("0xc000000000/2=", bit64.show(bit64.pide(a,b), 16))
	log.style(0)

	--将字符串转为 LongLong 数据
    if bit64.strtoll then
		local data = bit64.strtoll("864040064024194", 10)
		log.info("data", data:toHex())
		log.info("data", bit64.show(data))
	end
end

--获取高精度 tick，输出转换好的 64 位结构
local function sys_run_time()
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
