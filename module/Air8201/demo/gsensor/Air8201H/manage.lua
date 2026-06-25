
local manage = {}
-- 时间长度
local gtime = 64
-- 存储中断数据的两个buff
local gs = zbuff.create(gtime * 2, 0x30)
local gs2 = zbuff.create(gtime * 2, 0x30)
-- 最后一次中断的时间, 百万秒, 秒
local tprev = {0,0}
-- 检查静止状态变化的定时器
local gtimeid = nil
-- 是否打印日志
local logSwitch = true
local moduleName = "manage"

-- 获取当前运动状态
function manage.isRun()
    return isRun
end

local function logF(...)
    if logSwitch then
        log.info(moduleName, ...)
    end
end

local function gsensor_check()
    local tcount = 0
    logF("gsensor num",gs[0],gs[1],gs[2],gs[3],gs[4])
    -- 当前是静止状态的话, 判断最近5秒的震动情况
    if not isRun then
        if gs[0] + gs[1] + gs[2] + gs[3] + gs[4] - 0x30*5 > 4 then
            isRun = true
            logF("gsensor", "中断检查", "进入运动状态")
            sys.publish("SYS_STATUS_RUN", true)
            return
        end
    end
    -- 当前是运动状态
    for i = 0, gtime-1 do
        if gs[i] ~= 0 then
            tcount = tcount + 1
        end
    end
    if tcount < 4 then
        isRun = false
        logF("gsensor", "中断检查", "回到静止状态")
        -- sys.publish("GSENSOR_INC", "DOWN")
    end
end

function gsensor()
    -- logF("logSwitch", "中断", gs:toStr(0, gtime))
    -- logF("gsensorState",isRun)
    local tnow = {mcu.ticks2(2)}
    local tdiff = tnow[2] - tprev[2]
    --logF("band", string.toHex(manage.getLastCrashLevel()))
    --logF("gsensor", tnow[2], tdiff, gs:toStr(0, gtime), isRun)
    if tnow[1] == tprev[1] and tnow[2] == tprev[2] then
        -- 跟上一次中断还在同一秒,就不需要处理了
        -- log.debug("gsensor", "依然是同一秒,不需要处理")
        return
    end
    if tnow[1] > tprev[1] or tdiff > gtime then
            -- 距离上一次中断已经超过60秒,那之前的数据都没有意义
            -- 直接设置当前秒为1,其他为0
            logF("gsensor", "距离上一次中断已经超过60秒,那之前的数据都没有意义")
            gs:clear(0x30)
            gs[0] = 0x31
            tprev = tnow
            gsensor_check()
            return
    end
    tprev = tnow
    -- 少于60秒, 那就得搬动数据了
    -- 首先, 把备用buff清空
    gs2:clear(0x30)
    -- 把原有数据拷贝过来
    gs2:copy(tdiff, gs, 0, gtime)
    gs2[0] = 0x31
    gs:clear(0x30)
    -- 交互数据
    gs2, gs = gs, gs2
    -- 计算指定时间区间内的震动情况
    gsensor_check()
    -- 还需要一个定时, 解决运动后变回静止状态
    if gtimeid then
        sys.timerStop(gtimeid)
        gtimeid = nil
    end

    if not isRun then
        return
    end

    -- 如果当前是运动状态, 启动定时器
    local tt = 0
    local tt2 = 0
    for i = 2, gtime - 4 do
        if gs[i] ~= 0x30 then
            tt = tt + 1
            tt2 = i
            if tt > 2 then
                break
            end
        end
    end
    local ttime = (gtime - 4 - tt2)*1000
    logF("gsensor", "静止状态监听定时器", ttime, isRun)
    gtimeid = sys.timerStart(function()
        gs:clear(0x30)
        logF("gsensor", "定时器回调", "回到静止状态")
        gtimeid = nil
        isRun = false
        -- sys.publish("GSENSOR_INC", "DOWN")
    end, ttime)
end


return manage
