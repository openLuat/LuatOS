--[[
@module  airlink_mobile_info
@summary 通过 airlink 获取 Air780EPM 的 mobile 信息
@version 1.0
@date    2026.03.17
@author  LuatOS
@usage
本模块用于通过 airlink 接口获取 Air780EPM 的 mobile 信息（如 csq、imei 等），
并在 Air1601 端存储这些信息供其他模块使用。
]]

local airlink_mobile_info = {}

-- 存储 Air780EPM 的 mobile 信息
local mobile_info = {
    csq = -1,
    imei = "unknown",
    iccid = "unknown",
    imsi = "unknown",
    ip = "unknown",
    auto = false
}

-- 解析从 Air780EPM 接收到的 mobile 信息
local function parse_mobile_info(data)
    -- 数据格式: "MOBILE_INFO:csq=XX,imei=XXXXXXXXXXXXXXXX,iccid=XXXXXXXXXXXXXXXX,imsi=XXXXXXXXXXXXXXXX,ip=XXX.XXX.XXX.XXX"
    log.info("airlink_mobile_info", "接收到MOBILE_INFO数据:", data)
    local csq = data:match("csq=(%d+)")
    local imei = data:match("imei=([^,]+)")
    local iccid = data:match("iccid=([^,]+)")
    local imsi = data:match("imsi=([^,]+)")
    local ip = data:match("ip=([^,]+)")
    local auto = data:match("auto=([^,]+)")

    if csq then
        mobile_info.csq = tonumber(csq)
        log.info("airlink_mobile_info", "更新 csq:", mobile_info.csq)
    end
    if imei then
        mobile_info.imei = imei
        log.info("airlink_mobile_info", "更新 imei:", mobile_info.imei)
    end
    if iccid then
        mobile_info.iccid = iccid
        log.info("airlink_mobile_info", "更新 iccid:", mobile_info.iccid)
    end
    if imsi then
        mobile_info.imsi = imsi
        log.info("airlink_mobile_info", "更新 imsi:", mobile_info.imsi)
    end
    if ip then
        mobile_info.ip = ip
        log.info("airlink_mobile_info", "更新 ip:", mobile_info.ip)
    end
    if auto then
        mobile_info.auto = auto == "true"
        log.info("airlink_mobile_info", "更新 auto:", mobile_info.auto)
    end

    -- 发布更新事件
    log.info("airlink_mobile_info", "发布AIRLINK_MOBILE_INFO_UPDATED事件")
    sys.publish("AIRLINK_MOBILE_INFO_UPDATED", mobile_info)
end

-- 订阅 airlink 的 SDATA 事件
sys.subscribe("AIRLINK_SDATA", function(data)
    if type(data) == "string" and data:find("MOBILE_INFO:") then
        parse_mobile_info(data)
    end
end)

-- 获取 csq
function airlink_mobile_info.get_csq()
    return mobile_info.csq
end

-- 获取 imei
function airlink_mobile_info.get_imei()
    return mobile_info.imei
end

-- 获取 iccid
function airlink_mobile_info.get_iccid()
    return mobile_info.iccid
end

-- 获取 imsi
function airlink_mobile_info.get_imsi()
    return mobile_info.imsi
end

-- 获取 ip
function airlink_mobile_info.get_ip()
    return mobile_info.ip
end

-- 获取 auto
function airlink_mobile_info.get_auto()
    return mobile_info.auto
end

-- 获取所有信息
function airlink_mobile_info.get_all()
    return mobile_info
end

return airlink_mobile_info