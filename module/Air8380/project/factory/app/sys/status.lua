--[[
@module  status
@summary 运行状态聚合（供 AirCloud 上报使用）
@version 1.0
@date    2026.10.20

所有取值都用 pcall 包一层：某一路 API 不可用（如未插卡取不到 ICCID）时
只让该字段为 "--"，不能让整个状态页面或上报流程失败。
]]

local board = require "board"
local app_config = require "app_config"
local net_drv = require "net_drv"
local storage = require "storage"

local M = {}

local function safe(fn, default)
    local ok, v = pcall(fn)
    if ok and v ~= nil then return v end
    return default
end

local boot_ts = os.time()

-- 设备/固件信息
function M.device()
    return {
        model = board.model,
        mcu = board.mcu,
        project = PROJECT,
        version = VERSION,
        core = safe(function() return rtos.version() end, "--"),
        imei = safe(function() return mobile.imei() end, "--"),
        muid = safe(function() return mobile.muid and mobile.muid() or nil end, "--"),
        iccid = safe(function() return mobile.iccid() end, "--"),
        imsi = safe(function() return mobile.imsi() end, "--"),
        operator = net_drv.get_operator(),
    }
end

-- 网络信息
function M.network()
    local n = net_drv.state
    local function ip_of(adapter)
        return safe(function()
            local ip = socket.localIP(adapter)
            if ip == "0.0.0.0" then return "--" end
            return ip
        end, "--")
    end
    return {
        active = n.active or "无",
        eth_ready = n.eth_ready,
        wifi_ready = n.wifi_ready,
        gprs_ready = n.gprs_ready,
        eth_ip = ip_of(socket.LWIP_ETH),
        wifi_ip = ip_of(socket.LWIP_STA),
        csq = safe(function() return mobile.csq() end, 0),
        rssi = safe(function() return mobile.rssi() end, 0),
        wifi_ssid = app_config.load().wifi_ssid,
    }
end

-- 硬件/系统信息
function M.system()
    local cpu = safe(function()
        adc.open(adc.CH_CPU)
        local v = adc.get(adc.CH_CPU)
        adc.close(adc.CH_CPU)
        return v / 1000
    end, nil)
    local vbat = safe(function()
        adc.open(adc.CH_VBAT)
        local v = adc.get(adc.CH_VBAT)
        adc.close(adc.CH_VBAT)
        return v
    end, nil)
    -- rtos.meminfo 返回 (total, used)
    local ok_sys, mem_total, mem_used = pcall(rtos.meminfo, "sys")
    if not ok_sys then mem_total, mem_used = nil, nil end
    local ok_ps, psram_total, psram_used = pcall(rtos.meminfo, "psram")
    if not ok_ps then psram_total, psram_used = nil, nil end
    local up = safe(function()
        if os.time() > boot_ts then return os.time() - boot_ts end
        return 0
    end, 0)
    return {
        cpu_temp = cpu,
        vbat = vbat,
        mem_used = mem_used,
        mem_total = mem_total,
        psram_used = psram_used,
        psram_total = psram_total,
        uptime = up,
        time = safe(function() return os.date("%Y-%m-%d %H:%M:%S") end, "--"),
        flash_mounted = storage.is_mounted(),
    }
end

function M.snapshot()
    return {
        device = M.device(),
        network = M.network(),
        system = M.system(),
        config = app_config.get_masked(),
    }
end

return M
