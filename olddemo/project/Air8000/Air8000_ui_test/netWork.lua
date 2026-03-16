local netWork = {}
local moduleName = "netWork"
local logSwitch = true
local ipReady, simReady, timeSync = false, false, false
local isFlyMode = false
local cellInfo
local function logF(...)
    if logSwitch then
        log.info(moduleName, ...)
    end
end

local function ipReadyInd()
    logF("ipReadyInd")
    ipReady = true
end

local function ipLoseInd()
    logF("ipLoseInd")
    ipReady = false
end

local function timeSyncInd(time)
    timeSync = true
end

local function simStatusInd(status)
    logF("simStatusInd", status)
    if status == "RDY" then
        simReady = true
    elseif status == "NORDY" then
        simReady = false
    end
end

-- sys.taskInit(function()
--     while true do
--         mobile.reqCellInfo(15)
--         sys.wait(3 * 60 * 1000)
--     end
-- end)

-- sys.taskInit(function()
--     sys.wait(15000)
--     while true do
--         wlan.scan()
--         sys.wait(5 * 60 * 1000)
--     end
-- end)
sys.subscribe("CELL_INFO_UPDATE", function()
    cellInfo = mobile.getCellInfo()
    logF("CELL_INFO_UPDATE")
end)

function netWork.isReady()
    return ipReady
end

function netWork.simReady()
    return simReady
end

function netWork.getCellInfo()
    return cellInfo
end

function netWork.timeSync()
    return timeSync
end

function netWork.setFlyMode(onoff)
    if onoff then
        if chip == "EC718UM" or chip == "EC718HM" then
            log.info("vsim", "因为开启的vsim, 不允许进入飞行模式")
        end
        if not isFlyMode then
            isFlyMode = true
            mobile.flymode(0, true)
        end
    else
        if isFlyMode then
            isFlyMode = false
            mobile.flymode(0, false)
        end
    end
end

sys.subscribe("IP_READY", ipReadyInd)
sys.subscribe("IP_LOSE", ipLoseInd)
sys.subscribe("SIM_IND", simStatusInd)
sys.subscribe("NTP_UPDATE", timeSyncInd)

return netWork
