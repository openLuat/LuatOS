--[[
@module  sms_callback
@summary 短信事件本地调试日志功能模块
@version 1.0
@date    2026.08.06
@author  王城钧
@usage
本文件为短信事件本地调试日志功能模块，核心业务逻辑为：
1、订阅短信事件SMS_SENT，打印短信发送结果（SMSC是否接受，msq_ref等）；
2、订阅短信事件SMS_REPORT，打印短信投递状态报告（送达成功/失败/空号等）；
3、以上日志用于真机联调时观察短信链路的实时状态；

本文件没有对外接口，直接在main.lua中require "sms_callback"就可以加载运行；
]]

sys.subscribe("SMS_SENT", function(result, rp_cause, rp_cause_str, msg_ref, error_code)
    log.info("SMS_SENT", "result=", result, "rp_cause=", rp_cause, "msg_ref=", msg_ref, "error_code=", error_code)
    if result then
        log.info("SMS_SENT", "SMSC已接受, msg_ref=", msg_ref, "等待回执...")
    else
        log.info("SMS_SENT", "发送失败", rp_cause_str or "", "error_code=", error_code)
    end
end)

sys.subscribe("SMS_REPORT", function(msg_ref, status, status_str, phone, discharge_time)
    log.info("SMS_REPORT", "msg_ref=", msg_ref, "status=", status, "str=", status_str, "phone=", phone, "time=", discharge_time)
    if status == 0 then
        log.info("SMS_REPORT", "送达成功", phone, discharge_time)
    elseif status == 0x22 then
        log.info("SMS_REPORT", "用户不在线/关机", phone)
    elseif status == 0x23 then
        log.info("SMS_REPORT", "服务拒绝(可能停机)", phone)
    elseif status == 0x41 then
        log.info("SMS_REPORT", "目标不可达(空号)", phone)
    elseif status == 0x43 then
        log.info("SMS_REPORT", "无法获取(可能空号/停机)", phone)
    else
        log.info("SMS_REPORT", "送达失败", status_str, phone)
    end
end)

log.info("sms_callback", "已加载")
