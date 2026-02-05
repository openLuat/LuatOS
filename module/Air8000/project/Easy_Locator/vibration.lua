--[[
@module  vibration
@summary 利用加速度传感器da221实现静止/运动状态检测
@version 1.0
@date    2025.01.27
@usage
本模块替换原有的manage.lua中的静止状态监听逻辑
提供更准确的静止/运动状态判断，支持有效震动检测
]]

local vibration = {}

-- 引入exvib库
local exvib = require("exvib")

-- 中断引脚 - 使用WAKEUP2
local intPin = gpio.WAKEUP2

-- 是否正在运动
local isRun = false

-- 静止检测相关参数
local staticCheckTimer = nil     -- 静止检测定时器
local lastVibrationTime = 0      -- 最后一次振动时间
local staticDuration = 0         -- 静止持续时间(秒)

-- 振动检测相关参数
local tickCount = 0              -- 秒计数器
local vibrationHistory = {}      -- 振动历史记录(存储10次触发时间)
local effectiveVibrationFlag = false -- 有效震动标志
local effectiveVibrationCooldownTimer = nil -- 有效震动冷却定时器

-- 运动检测相关参数
local motionHistory = {}         -- 运动历史记录
local motionCheckIndex = 0

local logSwitch = true
local moduleName = "vibration"

local function logF(...)
    if logSwitch then
        log.info(moduleName, ...)
    end
end

--[[
获取当前运动状态
@return boolean true表示运动中，false表示静止
]]
function vibration.isRun()
    return isRun
end

--[[
获取静止持续时间(秒)
@return number 静止持续时间
]]
function vibration.getStaticDuration()
    return staticDuration
end

-- 秒计数器，用于时间统计
local function tickCounter()
    tickCount = tickCount + 1
    -- 如果是静止状态，增加静止持续时间
    if not isRun then
        staticDuration = staticDuration + 1
    end
end

-- 启动秒计数器
sys.timerLoopStart(tickCounter, 1000)

--[[
有效震动判断逻辑
检测10秒内是否触发5次以上的震动
]]
local function effectiveVibrationCheck()
    -- 保留最近10次的振动时间
    if #vibrationHistory >= 10 then
        table.remove(vibrationHistory, 1)
    end
    table.insert(vibrationHistory, tickCount)

    logF("vibration", "触发次数", #vibrationHistory, "tick", tickCount)

    -- 检查最近5次是否在10秒内
    if #vibrationHistory >= 5 then
        local oldest = vibrationHistory[1]
        local newest = vibrationHistory[#vibrationHistory]
        local timeDiff = newest - oldest

        if timeDiff < 10 and oldest > 0 then
            logF("vibration", "检测到有效震动", "时间差", timeDiff, "秒")
            -- 触发有效震动事件
            if not effectiveVibrationFlag then
                effectiveVibrationFlag = true
                sys.publish("EFFECTIVE_VIBRATION")
                -- 30分钟冷却期
                sys.timerStart(function()
                    effectiveVibrationFlag = false
                    logF("vibration", "有效震动冷却结束")
                end, 30 * 60 * 1000)
            end
        end
    end
end

--[[
静止/运动状态检测逻辑
]]
local function motionCheck()
    -- 保留最近30次的振动时间用于运动检测（扩大缓存）
    if #motionHistory >= 30 then
        table.remove(motionHistory, 1)
    end
    table.insert(motionHistory, tickCount)

    local vibrationCount = 0
    -- 统计最近20秒内的振动次数（从10秒改为20秒，更宽松）
    for i = #motionHistory, 1, -1 do
        if tickCount - motionHistory[i] <= 20 then
            vibrationCount = vibrationCount + 1
        else
            break
        end
    end

    logF("vibration", "20秒内振动次数", vibrationCount, "当前状态", isRun)

    -- 静止 -> 运动 判断
    if not isRun then
        -- 静止状态下，如果在5秒内有2次以上振动，则认为开始运动
        local recentVibrationCount = 0
        for i = #motionHistory, 1, -1 do
            if tickCount - motionHistory[i] <= 5 then
                recentVibrationCount = recentVibrationCount + 1
            else
                break
            end
        end

        if recentVibrationCount >= 2 then
            isRun = true
            staticDuration = 0
            logF("vibration", "进入运动状态", "isRun:", isRun)
            sys.publish("SYS_STATUS_RUN")  -- 只在静止→运动时发布事件,不携带参数
        end
    else
        -- 运动 -> 静止 判断
        -- 修改：只有20秒内完全没有振动，才认为回到静止
        -- 避免正常行走时因振动间隔稍长被误判为静止
        if vibrationCount == 0 then
            isRun = false
            logF("vibration", "回到静止状态", "20秒内无振动")
            -- 不发布事件,让common.lua通过manage.isRun()检测状态变化
        end
    end

    -- 如果当前是运动状态，设置定时器检测回到静止
    if isRun then
        if staticCheckTimer then
            sys.timerStop(staticCheckTimer)
            staticCheckTimer = nil
        end

        -- 检查最后几次振动的时间间隔，判断何时进入静止
        local lastVibIndex = #motionHistory
        local lastVibTime = motionHistory[lastVibIndex]
        if lastVibTime then
            local timeToStatic = (20 - (tickCount - lastVibTime)) * 1000

            if timeToStatic > 0 and timeToStatic <= 20000 then
                logF("vibration", "设置静止检测定时器", timeToStatic, "ms")
                staticCheckTimer = sys.timerStart(function()
                    -- 重新检查20秒内的振动次数
                    local finalCheckCount = 0
                    for i = #motionHistory, 1, -1 do
                        if tickCount - motionHistory[i] <= 20 then
                            finalCheckCount = finalCheckCount + 1
                        else
                            break
                        end
                    end

                    if finalCheckCount == 0 then
                        isRun = false
                        logF("vibration", "定时器回调，回到静止状态")
                        -- 不发布事件,让common.lua通过manage.isRun()检测状态变化
                    end
                    staticCheckTimer = nil
                end, timeToStatic)
            end
        end
    end
end

--[[
中断处理函数
]]
local function interruptCallback()
    logF("interrupt", gpio.get(intPin))
    if gpio.get(intPin) == 1 then
        -- 读取xyz三轴数据
        local x, y, z = exvib.read_xyz()
        if x and y and z then
            logF("vibration", "xyz", x..'g', y..'g', z..'g')
        end

        -- 更新最后振动时间
        lastVibrationTime = tickCount

        -- 执行有效震动检测
        effectiveVibrationCheck()

        -- 执行静止/运动状态检测
        motionCheck()
    end
end

--[[
初始化vibration模块
]]
function vibration.init()
    logF("vibration", "初始化开始")

    -- 初始化exvib库，参数1表示运动检测模式(4g量程)
    exvib.open(1)

    -- 设置GPIO防抖100ms
    gpio.debounce(intPin, 100)

    -- 设置GPIO中断，WAKEUP2默认双边沿触发
    gpio.setup(intPin, interruptCallback)

    logF("vibration", "初始化完成")
end

--[[
关闭vibration模块
]]
function vibration.close()
    if staticCheckTimer then
        sys.timerStop(staticCheckTimer)
        staticCheckTimer = nil
    end
    if effectiveVibrationCooldownTimer then
        sys.timerStop(effectiveVibrationCooldownTimer)
        effectiveVibrationCooldownTimer = nil
    end
    gpio.close(intPin)
    exvib.close()
    logF("vibration", "已关闭")
end

--[[
获取崩溃级别数据(兼容原有manage.lua接口)
@return string 崩溃级别数据
]]
function vibration.getLastCrashLevel()
    -- 返回空的字节数据，可根据需要实现
    return string.char(0, 0, 0, 0, 0, 0, 0, 0)
end

-- 初始化模块
sys.taskInit(function()
    sys.wait(1000) -- 等待系统初始化完成
    vibration.init()
end)

return vibration
