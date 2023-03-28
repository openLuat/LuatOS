
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "bit64_test"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- 引入必要的库文件(lua编写), 内部库不需要require
sys = require("sys")

if wdt then
    --添加硬狗防止程序卡死，在支持的设备上启用这个功能
    wdt.init(9000)--初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000)--3s喂一次狗
end


local data,b64,b32,a,b

if bit64 then
	log.style(1)
	log.info("bit64 演示")
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


	a = bit64.to64(87654321)
	b = bit64.to64(12345678)
	log.info("87654321+12345678=", bit64.show(bit64.plus(a,b)))
	log.info("87654321-12345678=", bit64.show(bit64.minus(a,b)))
	log.info("87654321*12345678=", bit64.show(bit64.multi(a,b)))
	log.info("87654321/12345678=", bit64.show(bit64.pide(a,b)))

	a = bit64.to64(87654321)
	b = 1234567
	log.info("87654321+1234567=", bit64.show(bit64.plus(a,b)))
	log.info("87654321-1234567=", bit64.show(bit64.minus(a,b)))
	log.info("87654321*1234567=", bit64.show(bit64.multi(a,b)))
	log.info("87654321/1234567=", bit64.show(bit64.pide(a,b)))


	a = bit64.to64(87654.326)
	b = bit64.to64(12345)
	log.info("87654.326+12345=", 87654.326 + 12345)
	log.info("87654.326+12345=", bit64.show(bit64.plus(a,b)))
	log.info("87654.326-12345=", bit64.show(bit64.minus(a,b)))
	log.info("87654.326*12345=", bit64.show(bit64.multi(a,b)))
	log.info("87654.326/12345=", bit64.show(bit64.pide(a,b)))

	a = bit64.to64(87654.32)
	b = bit64.to64(12345.67)
	log.info("float", "87654.32+12345.67=", 87654.32 + 12345.67)
	log.info("double","87654.32+12345.67=", bit64.show(bit64.plus(a,b)))
	log.info("double to float","87654.32+12345.67=", bit64.to32(bit64.plus(a,b)))
	log.info("87654.32-12345.67=", bit64.show(bit64.minus(a,b)))
	log.info("87654.32*12345.67=", bit64.show(bit64.multi(a,b)))
	log.info("87654.32/12345.67=", bit64.show(bit64.pide(a,b)))
	log.info("double to int64", "87654.32/12345.67=", bit64.show(bit64.pide(a,b,nil,true)))

	a = bit64.to64(0xc0000000)
	b = 2
	a = bit64.shift(a,8,true)
	log.info("0xc0000000 << 8 =", bit64.show(a, 16))
	log.info("0xc000000000+2=", bit64.show(bit64.plus(a,b), 16))
	log.info("0xc000000000-2=", bit64.show(bit64.minus(a,b), 16))
	log.info("0xc000000000*2=", bit64.show(bit64.multi(a,b), 16))
	log.info("0xc000000000/2=", bit64.show(bit64.pide(a,b), 16))
	log.style(0)
end

local function sys_run_time()
	local tick64, per = mcu.tick64(true)
	local per_cnt = per * 1000000
	while true do
		tick64, per = mcu.tick64(true)
		log.info("work time","当前时间", bit64.to32(bit64.pide(tick64,per_cnt)))
		sys.wait(1000)
	end
end

if mcu.tick64() then
	sys.taskInit(sys_run_time)
end

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!