--[[
@module  sms_bridge
@summary 短信与AirCloud协议桥接功能模块
@version 1.0
@date    2026.08.06
@author  王城钧
@usage
本文件为短信与AirCloud协议桥接功能模块，核心业务逻辑为：
1、订阅短信事件SMS_SENT，设备发送短信被SMSC接受后，将发送结果转换为TLV报文上传云平台；
2、订阅短信事件SMS_REPORT，短信投递状态报告到达后，将送达状态转换为TLV报文上传云平台；
3、订阅短信事件SMS_INC，设备收到新短信后，将短信内容转换为TLV报文上传云平台；
4、处理云平台下发的短信指令（SMS_SEND），调起模组短信能力（sms.send/sms.sendLong）向目标号码发送短信；
5、维护msg_ref到平台seq的绑定关系，确保投递状态报告能关联到原始发送消息；

本文件对外接口有两个：
1、sms_bridge.send_sms(callee, content) - 发送短信，调用sms.send接口；
2、sms_bridge.handle_message(tlvs) - 处理云平台下发的TLV消息；
]]

local sms_bridge = {}

-- 变量
local excloud = require("excloud")
local FIELD = excloud.FIELD_MEANINGS
local DTYPE = excloud.DATA_TYPES
local _seq = 0

-- 平台下发的流水号 + 号码 + 内容（sms.send 时暂存，SMS_SENT 回调时取出上报）
local _pending_seq = ""
local _pending_callee = ""
local _pending_content = ""

-- msg_ref → 平台 seq 绑定表（SMS_SENT 时写入，SMS_REPORT 时查表取出原 seq）
local _bindings = {}

local SMS_STATUS_MAP = {
    [0]    = "发送成功",
    [1]    = "发送失败",
    [0x22] = "不在线/关机",
    [0x23] = "服务拒绝(停机)",
    [0x41] = "目标不可达(空号/离线)",
    [0x43] = "无法获取",
    [0x46] = "有效期过期",
}

-- 内部函数
local function send_tlvs(tlvs)
    local ok, err = excloud.send(tlvs, false)
    if not ok then
        log.warn("sms_bridge", "TLV发送失败", err)
    end
end

local function mtn(tag, ...)
    excloud.mtn_log(tag, ...)
end

-- 事件订阅
sys.subscribe("SMS_SENT", function(result, rp_cause, rp_cause_str, msg_ref, error_code)
    local plat_seq = _pending_seq or ""
    local status_str = result and SMS_STATUS_MAP[0] or SMS_STATUS_MAP[1]

    -- 绑定 msg_ref → 平台 seq（供 SMS_REPORT 查表）
    if msg_ref and plat_seq ~= "" then
        _bindings[msg_ref] = plat_seq
    end

    log.info("sms_bridge", "SMS_SENT上报", "plat_seq", plat_seq, "msg_ref", msg_ref, "status", status_str, "callee", _pending_callee)
    send_tlvs({
        { field_meaning = FIELD.SMS_SEND_RSP, data_type = DTYPE.INTEGER, value = 0 },
        { field_meaning = FIELD.SMS_SEQ,      data_type = DTYPE.ASCII,   value = plat_seq },
        { field_meaning = FIELD.SMS_CALLEE,   data_type = DTYPE.ASCII,   value = _pending_callee },
        { field_meaning = FIELD.SMS_CONTENT,  data_type = DTYPE.UNICODE, value = _pending_content },
        { field_meaning = FIELD.SMS_STATUS,   data_type = DTYPE.UNICODE, value = status_str },
        { field_meaning = FIELD.SMS_MSG_REF,  data_type = DTYPE.INTEGER, value = msg_ref or 0 },
    })
    mtn("sms", "SMS_SENT上报", "plat_seq", plat_seq, "msg_ref", msg_ref, "status", status_str, "callee", _pending_callee)
end)

sys.subscribe("SMS_REPORT", function(msg_ref, status, status_str, phone, discharge_time)
    local plat_seq = _bindings[msg_ref] or ""
    local report_status = SMS_STATUS_MAP[status] or status_str or ("未知状态:" .. tostring(status))

    log.info("sms_bridge", "SMS_REPORT上报", "plat_seq", plat_seq, "msg_ref", msg_ref, "status", report_status, "phone", phone)
    send_tlvs({
        { field_meaning = FIELD.SMS_REPORT,  data_type = DTYPE.INTEGER, value = 0 },
        { field_meaning = FIELD.SMS_SEQ,     data_type = DTYPE.ASCII,   value = plat_seq },
        { field_meaning = FIELD.SMS_CALLEE,  data_type = DTYPE.ASCII,   value = tostring(phone or "") },
        { field_meaning = FIELD.SMS_CONTENT, data_type = DTYPE.UNICODE, value = _pending_content },
        { field_meaning = FIELD.SMS_STATUS,  data_type = DTYPE.UNICODE, value = report_status },
        { field_meaning = FIELD.SMS_MSG_REF, data_type = DTYPE.INTEGER, value = msg_ref or 0 },
    })
    mtn("sms", "SMS_REPORT上报", "plat_seq", plat_seq, "msg_ref", msg_ref, "status", report_status, "phone", phone)
end)

sys.subscribe("SMS_INC", function(phone, content, metadata)
    if not phone then return end
    _seq = _seq + 1
    log.info("sms_bridge", "收到短信上报", phone, "seq=", _seq)
    send_tlvs({
        { field_meaning = FIELD.SMS_REPORT,  data_type = DTYPE.INTEGER, value = 0 },
        { field_meaning = FIELD.SMS_SEQ,     data_type = DTYPE.ASCII,   value = tostring(_seq) },
        { field_meaning = FIELD.SMS_CALLER,  data_type = DTYPE.ASCII,   value = tostring(phone) },
        { field_meaning = FIELD.SMS_CONTENT, data_type = DTYPE.UNICODE, value = tostring(content or "") },
    })
    mtn("sms", "收到短信上报", "phone", phone, "seq", _seq)

    if _G.ON_SMS_INCOMING then
        _G.ON_SMS_INCOMING(phone, content, metadata)
    end
end)

-- 公开接口
function sms_bridge.send_sms(callee, content)
    _pending_seq = tostring(os.time())  -- 本地发送无平台 seq，用时间戳占位
    _pending_callee = tostring(callee)
    _pending_content = tostring(content)
    return sms.send(tostring(callee), tostring(content), true, true)
end

function sms_bridge.handle_message(tlvs)
    if not tlvs then return end

    local is_sms_send = false
    for _, tlv in ipairs(tlvs) do
        if tlv.field == FIELD.SMS_SEND then
            is_sms_send = true
            break
        end
    end
    if not is_sms_send then return end

    local callee, content, seq, long_flag, long_total
    for _, tlv in ipairs(tlvs) do
        if tlv.field == FIELD.SMS_CALLEE then
            callee = tlv.value
        elseif tlv.field == FIELD.SMS_CONTENT then
            content = tlv.value
        elseif tlv.field == FIELD.SMS_SEQ then
            seq = tostring(tlv.value or "")
        elseif tlv.field == FIELD.SMS_LONG_FLAG then
            long_flag = tlv.value
        elseif tlv.field == FIELD.SMS_LONG_TOTAL then
            long_total = tlv.value
        end
    end

    if not callee or not content then
        log.warn("sms_bridge", "SMS_SEND缺少callee或content")
        send_tlvs({
            { field_meaning = FIELD.SMS_SEND_RSP, data_type = DTYPE.INTEGER, value = 0 },
            { field_meaning = FIELD.SMS_SEQ,      data_type = DTYPE.ASCII,   value = seq or "" },
            { field_meaning = FIELD.SMS_STATUS,   data_type = DTYPE.UNICODE, value = SMS_STATUS_MAP[1] },
        })
        return
    end

    log.info("sms_bridge", "下发短信", callee, "plat_seq=", seq, "long=", long_flag)
    mtn("sms", "收到平台下发短信", "callee", callee, "plat_seq", seq, "long_flag", long_flag)

    _pending_seq = seq
    _pending_callee = tostring(callee)
    _pending_content = tostring(content)

    if long_flag and long_flag == 1 and long_total and long_total > 1 then
        sys.taskInit(function()
            pcall(sms.sendLong, tostring(callee), tostring(content), true, true)
        end)
    else
        sms.send(tostring(callee), tostring(content), true, true)
    end
end

log.info("sms_bridge", "已加载")
return sms_bridge
