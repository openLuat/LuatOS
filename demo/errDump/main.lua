PROJECT = "errdump_test"
VERSION = "1.0"
PRODUCT_KEY = "s1uUnY6KA06ifIjcutm5oNbG3MZf5aUv" --换成自己的
-- sys库是标配
_G.sys = require("sys")
_G.sysplus = require("sysplus")
log.style(1)

--下面演示自动发送
errDump.config(true, 600, "user_id")	-- 默认是关闭，用这个可以额外添加用户标识，比如用户自定义的ID之类

-- local function test_user_log()
-- 	while true do
-- 		sys.wait(15000)
-- 		log.record("测试一下用户的记录功能")
-- 	end
-- end

-- local function test_error_log()
-- 	sys.wait(60000)
-- 	lllllllllog.record("测试一下用户的记录功能") --默认写错代码死机
-- end



-- 下面演示手动获取信息
errDump.config(true, 0)
local function test_user_log()
	local buff = zbuff.create(4096)
	local new_flag = errDump.dump(buff, errDump.TYPE_SYS)		-- 开机手动读取一次异常日志
	if buff:used() > 0 then
		log.info(buff:toStr(0, buff:used()))	-- 打印出异常日志
	end
	new_flag = errDump.dump(buff, errDump.TYPE_SYS)
	if not new_flag then
		log.info("没有新数据了，删除系统错误日志")
		errDump.dump(nil, errDump.TYPE_SYS, true)
	end
	while true do
		sys.wait(15000)
		errDump.record("测试一下用户的记录功能")
		local new_flag = errDump.dump(buff, errDump.TYPE_USR)
		if new_flag then
			log.info("errBuff", buff:toStr(0, buff:used()))
		end
		new_flag = errDump.dump(buff, errDump.TYPE_USR)
		if not new_flag then
			log.info("没有新数据了，删除用户错误日志")
			errDump.dump(nil, errDump.TYPE_USR, true)
		end

	end
end

local function test_error_log()
	sys.wait(60000)
	lllllllllog.record("测试一下用户的记录功能") --默认写错代码死机
end

sys.taskInit(test_user_log)
sys.taskInit(test_error_log)
sys.run()
