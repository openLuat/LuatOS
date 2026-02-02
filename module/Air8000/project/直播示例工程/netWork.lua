--[[
@module  netWork
@summary 网络状态管理模块：网络连接状态、SIM卡状态、基站信息
@version 1.0
@author  Auto
@usage
本模块实现以下功能：
1. 网络连接状态监控（IP_READY/IP_LOSE）
2. SIM卡状态监控（SIM_IND）
3. 时间同步状态监控（NTP_UPDATE）
4. 基站信息获取（CELL_INFO_UPDATE）
5. 飞行模式控制
]]

local netWork = {}
local moduleName = "netWork"
local logSwitch = true

-- ==================== 全局变量 ====================

-- 网络状态标志
local ipReady = false    -- IP是否就绪
local simReady = false   -- SIM卡是否就绪
local timeSync = false   -- 时间是否同步

-- 飞行模式标志
local isFlyMode = false

-- 基站信息缓存
local cellInfo

-- ==================== 内部函数 ====================

-- 本地日志函数
local function logF(...)
    if logSwitch then
        log.info(moduleName, ...)
    end
end

-- IP就绪事件处理
-- @usage sys.subscribe("IP_READY", ipReadyInd)
local function ipReadyInd()
    logF("ipReadyInd")
    ipReady = true
end

-- IP丢失事件处理
-- @usage sys.subscribe("IP_LOSE", ipLoseInd)
local function ipLoseInd()
    logF("ipLoseInd")
    ipReady = false
end

-- 时间同步事件处理
-- @param time 同步的时间戳
-- @usage sys.subscribe("NTP_UPDATE", timeSyncInd)
local function timeSyncInd(time)
    timeSync = true
end

-- SIM卡状态事件处理
-- @param status SIM卡状态：RDY=就绪，NORDY=未就绪
-- @usage sys.subscribe("SIM_IND", simStatusInd)
local function simStatusInd(status)
    logF("simStatusInd", status)
    if status == "RDY" then
        simReady = true
    elseif status == "NORDY" then
        simReady = false
    end
end

-- ==================== 事件订阅 ====================

-- 基站信息更新事件
sys.subscribe("CELL_INFO_UPDATE", function()
    cellInfo = mobile.getCellInfo()
    logF("CELL_INFO_UPDATE")
end)

-- ==================== 导出函数 ====================

-- 检查网络是否就绪
-- @return boolean true=IP已就绪，false=IP未就绪
function netWork.isReady()
    return ipReady
end

-- 检查SIM卡是否就绪
-- @return boolean true=SIM卡就绪，false=SIM卡未就绪
function netWork.simReady()
    return simReady
end

-- 获取基站信息
-- @return table 基站信息（包含mcc/mnc/tac/cid等）
function netWork.getCellInfo()
    return cellInfo
end

-- 检查时间是否已同步
-- @return boolean true=已同步，false=未同步
function netWork.timeSync()
    return timeSync
end

-- ==================== 事件订阅 ====================

-- 订阅系统网络事件
sys.subscribe("IP_READY", ipReadyInd)   -- IP就绪
sys.subscribe("IP_LOSE", ipLoseInd)     -- IP丢失
sys.subscribe("SIM_IND", simStatusInd)  -- SIM卡状态
sys.subscribe("NTP_UPDATE", timeSyncInd) -- 时间同步

return netWork
