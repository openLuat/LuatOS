
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "pack"
VERSION = "2.0.0"

--[[
本demo演示 string字符串的基本操作
1. lua的字符串是带长度, 这意味着, 它不依赖0x00作为结束字符串, 可以包含任意数据
2. lua的字符串是不可变的, 就不能直接修改字符串的一个字符, 修改字符会返回一个新的字符串
]]

-- sys库是标配
_G.sys = require("sys")
sysplus = require("sysplus")

-- Air780E的AT固件默认会为开机键防抖, 导致部分用户刷机很麻烦
if rtos.bsp() == "EC618" and pm and pm.PWK_MODE then
    pm.power(pm.PWK_MODE, false)
end

sys.taskInit(function ()
    sys.wait(1000) -- 免得看不到日志
    local tmp

	--实验1：以小端方式编码
	local data = string.pack("<I", 0xAABBCCDD)      --‘<’表示以小端方式编码，'I'表示，unsigned int , 4字节
	log.info("pack:", 	string.format("%02X", data:byte(1)), 	--输出小端编码后的数据
						string.format("%02X", data:byte(2)), 
						string.format("%02X", data:byte(3)), 
						string.format("%02X", data:byte(4)))
	
	--实验2：以大端方式编码
	local data = string.pack(">I", 0xAABBCCDD)
	log.info("pack:", 	string.format("%02X", data:byte(1)),   --输出大端编码后的数据
						string.format("%02X", data:byte(2)), 
						string.format("%02X", data:byte(3)), 
						string.format("%02X", data:byte(4)))
						
	--实验3：对上面已经完成的大端编码，再次进行解包为每个字节					
	local byte1,byte2,byte3,byte4 = string.unpack(">BBBB", data)  --将32位数据拆成4个8位字节数据
    --log.info("Unpack", byte1,byte2,byte3,byte4)		
	log.info("Unpack:", string.format("%02X", byte1),   --以十六进制形式输出拆解后的4个字节数据
						string.format("%02X", byte2), 
						string.format("%02X", byte3), 
						string.format("%02X", byte4))
end)
-- 这里演示4G模块上网后，会自动点亮网络灯，方便用户判断模块是否正常开机
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
