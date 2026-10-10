--[[
@module  device_info
@summary 设备/模组信息上报（每次开机首次鉴权成功后上报一次）
@version 1.0.0
@date    2026.09.11
@author  嵌入式软件设计开发代理
@usage
依据 requirement.md F-011 与 network-communication-protocol.md「设备信息上报」：
1. 订阅 AIRCLOUD_READY（鉴权成功）；
2. 每次开机运行过程中，仅在第一次鉴权成功后上报一次：
   - ICCID   : 字段 783（SIM_ICCID，ASCII）       来源 mobile.iccid()
   - 版本号   : 字段 1027（FIRMWARE_VERSION，ASCII）来源 rtos.firmware()+rtos.version(true)+PROJECT+VERSION
   - 开机原因 : 字段 776（BOOT_REASON，整数）      来源 pm.lastReson()（4 返回值打包，见下）
   之后同一进程内重复鉴权成功（重连）不再上报；重启后重新计数（内存标志，天然复位）。
3. 开机原因打包（pm.lastReson() 4 个返回值 → 4 字节大端：a b c dIdx）：
   - a（0~6）、b（0/3/4）、c（0~10）各占 1 字节；
   - d 的取值范围为 1/2/4/8/16/32/256/512（均为 2 的幂），故第 4 字节存其幂次
     dIdx = log2(d)（0~9），解码时 d = 2^dIdx，可无损还原；
   - 打包值 = a*2^24 + b*2^16 + c*2^8 + dIdx。
本模块无对外接口，直接 require "device_info" 即加载运行。
]]

local config_app  = require("config_app")
local msg_bus     = require("msg_bus")
local excloud_app = require("excloud_app")
local oam_logger  = require("oam_logger")

local FM = config_app.FIELD_MEANINGS
local DT = config_app.DATA_TYPES

-- 本进程是否已上报（内存标志：重启后自动复位，实现“每次开机仅上报一次”）
local reported = false

-- 组装版本号字符串：内核固件名_数字版本 + 空格 + 脚本项目名 + 空格 + 脚本版本号
local function build_version_string()
    local fw_name = rtos.firmware() or ""
    local _, fw_num = rtos.version(true)
    local project = _G.PROJECT or "unknown"
    local version = _G.VERSION or "0.0.0"
    return fw_name .. "_" .. tostring(fw_num or "") .. " " .. project .. " " .. version
end

-- 求 d 的幂次 k（d = 2^k；d<=0 返回 0），结果 ≤9，可放进 1 字节
local function log2_of_pow(d)
    local k = 0
    local v = d or 0
    while v > 1 do
        v = v / 2
        k = k + 1
    end
    return k
end

-- 打包 pm.lastReson() 的 4 个返回值 → 4 字节整数：a*2^24 + b*2^16 + c*2^8 + dIdx
local function pack_boot_reason()
    local a, b, c, d = 0, 0, 0, 0
    if pm and pm.lastReson then
        local ok, ra, rb, rc, rd = pcall(pm.lastReson)
        if ok then
            a = ra or 0
            b = rb or 0
            c = rc or 0
            d = rd or 0
        end
    end
    local d_idx = log2_of_pow(d)
    return a * 16777216 + b * 65536 + c * 256 + d_idx
end

-- 组装本次上报的 TLV 列表（取不到的项跳过）
local function build_tlvs(version_str)
    local tlvs = {}

    -- ICCID（783）：模拟器等无 mobile.iccid 时跳过
    if mobile and mobile.iccid then
        local iccid = mobile.iccid()
        if iccid and #iccid > 0 then
            tlvs[#tlvs + 1] = { field_meaning = FM.SIM_ICCID, data_type = DT.ASCII, value = iccid }
        else
            log.warn("device_info", "ICCID 为空，跳过该项")
        end
    else
        log.warn("device_info", "当前环境无 mobile.iccid 接口，跳过 ICCID")
    end

    -- 版本号（1027）
    tlvs[#tlvs + 1] = { field_meaning = FM.FIRMWARE_VERSION, data_type = DT.ASCII, value = version_str }

    -- 开机原因（776，4 返回值打包）
    tlvs[#tlvs + 1] = { field_meaning = FM.BOOT_REASON, data_type = DT.INTEGER, value = pack_boot_reason() }

    return tlvs
end

-- 上报一次（本进程内仅一次）
local function report_device_info()
    if reported then
        return
    end
    reported = true

    local version_str = build_version_string()
    local tlvs = build_tlvs(version_str)
    local ok, err = excloud_app.send_tlv(tlvs, false)
    if ok then
        log.info("device_info", "设备信息上报成功", "字段数", #tlvs, "版本", version_str)
        oam_logger.log("device", "设备信息上报", version_str)
    else
        log.warn("device_info", "设备信息上报失败", err)
    end
end

-- 鉴权成功回调
local function on_aircloud_ready()
    report_device_info()
end

sys.subscribe(msg_bus.AIRCLOUD_READY, on_aircloud_ready)
