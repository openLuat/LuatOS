--[[
@module  sms_app
@summary 短信测试应用功能模块
@version 1.0
@date    2026.08.06
@author  王城钧
@usage
本文件为短信测试应用功能模块，核心业务逻辑为：
1、开机等待8秒钟后，自动执行上行短信测试用例；
2、调用sms_bridge.send_sms向指定号码发送短信，验证短信上行链路是否正常；
3、测试结束后打印结果日志；

本文件没有对外接口，直接在main.lua中require "sms_app"就可以加载运行；
]]

-- 变量
local excloud = require("excloud")
local sms_bridge = require("sms_bridge")

local SMS_TEST_UPLINK   = true


-- 上行测试：设备直接发送短信
if SMS_TEST_UPLINK then
    sys.taskInit(function()
        sys.wait(8000)
        log.info("test_app", "=== 上行测试开始 ===")
        sms_bridge.send_sms("17538215008", "301")
        sys.waitUntil("SMS_SENT")
        sys.wait(1000)
        sms_bridge.send_sms("10001", "102")
    end)
end



log.info("test_app", "已加载", "上行=", SMS_TEST_UPLINK)
