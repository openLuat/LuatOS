--[[
本功能模块演示的内容为：
使用Air8101开发板来演示errdump日志上报功能
使用自动上报异常日志到iot平台
]]
-- 统一联网函数
sys.taskInit(function()
    sys.wait(1000)
    -----------------------------
    ---------wifi 联网-----------
    -----------------------------
    if wlan and wlan.connect then
        -- wifi 联网, ESP32系列均支持
        local ssid = "kfyy123"
        local password = "kfyy123456"
        log.info("wifi", ssid, password)
        -- TODO 改成esptouch配网
        -- LED = gpio.setup(12, 0, gpio.PULLUP)
        wlan.init()
        wlan.setMode(wlan.STATION)
        wlan.connect(ssid, password, 1)
        local result, data = sys.waitUntil("IP_READY")
        log.info("wlan", "IP_READY", result, data)
        device_id = wlan.getMac()
    end
    log.info("已联网")
    sys.publish("net_ready")
end)



local function test_user_log()
	sys.waitUntil("net_ready") --等待网络连接成功
	-- 下面演示自动发送异常日志到iot平台
	errDump.config(true, 600, "user_id") -- 默认是关闭，用这个可以额外添加用户标识，比如用户自定义的ID之类
	while true do
		sys.wait(15000)
		errDump.record("测试一下用户的记录功能")
	end
end

local function test_error_log() --故意写错用来触发系统异常日志记录
	sys.wait(60000)
	lllllllllog.info("测试一下用户的记录功能") --默认写错代码死机
end

sys.taskInit(test_user_log) -- 启动errdemp测试任务
sys.taskInit(test_error_log)--启动错误函数任务


