--[[
@module  manage
@summary 设备管理模块：功耗管理、按键控制、运动状态检测
@version 1.0
@author  Auto
@usage
本模块实现以下功能：
1. 功耗管理：基于引用计数机制的唤醒/休眠管理
2. 按键控制：长按3秒关机
3. 运动状态：集成vibration模块，检测静止/运动状态
4. 关机管理：发布关机事件，进入飞行模式
]]

local logSwitch = false
local moduleName = "manage"

-- 模块休眠tag管理表（引用计数）
-- key: tag名称（如"READ_GNSS_DATA", "charge"等）
-- value: 1=唤醒计数，0=休眠
local tags = {}

-- 模块是否处于休眠状态
-- true=休眠中，false=唤醒状态
local pmFlag = true

-- GSensor和GNSS的备电控制GPIO（GPIO 24）
local GSensorAndGnssVBackUp = gpio.setup(24, 1, gpio.PULLUP)

-- 默认开启备电
GSensorAndGnssVBackUp(1)

-- 引入vibration模块并挂载到全局环境
_G.vibration = require "vibration"

-- 模块导出表
local manage = {}

-- 本地日志函数
local function logF(...)
    if logSwitch then
        log.info(moduleName, ...)
    end
end

-- 发布关机消息，执行关机流程
-- @usage manage.powerOff() -- 发布SYS_SHUTDOWN事件
function manage.powerOff()
    sys.publish("SYS_SHUTDOWN")
end

-- 电源按键中断回调函数
-- 长按3秒触发关机，松开取消
-- @usage gpio.setup(46, pwrkeyCb, gpio.PULLUP, gpio.BOTH)
local function pwrkeyCb()
    if gpio.get(46) == 1 then
        -- 按键松开：取消关机定时器
        if sys.timerIsActive(manage.powerOff) then
            sys.timerStop(manage.powerOff)
            sys.publish("EXIT_FLYMODE")  -- 退出飞行模式
        end
    else
        -- 按键按下：启动3秒关机定时器
        sys.timerStart(manage.powerOff, 3000)
    end
end

-- 获取崩溃级别数据（兼容旧接口）
-- @return string 崩溃级别数据（8字节）
function manage.getLastCrashLevel()
    return vibration.getLastCrashLevel()
end

-- 获取当前运动状态
-- @return boolean true=运动中，false=静止
function manage.isRun()
    return vibration.isRun()
end

-- 获取静止持续时间
-- @return number 静止持续时间（秒）
function manage.getStaticDuration()
    return vibration.getStaticDuration()
end

-- 模块唤醒（引用计数唤醒）
-- @param string tag 唤醒标签，用于引用计数管理
-- @usage manage.wake("READ_GNSS_DATA") -- 唤醒GNSS数据读取功能
-- @usage manage.wake("charge") -- 充电时唤醒
function manage.wake(tag)
    assert(tag and tag ~= nil, "pm.wake tag invalid")
    tags[tag] = 1  -- 增加唤醒计数

    -- 如果之前处于休眠状态，执行唤醒操作
    if pmFlag == true then
        logF("pm wake")
        pmFlag = false
        pm.power(pm.WORK_MODE, 0)  -- 设置为工作模式
        sys.publish("SYS_WAKE_STATUS", true)  -- 发布唤醒状态事件
    end
end

-- 模块休眠（引用计数休眠）
-- @param string tag 休眠标签，用于引用计数管理
-- @usage manage.sleep("READ_GNSS_DATA") -- 休眠GNSS数据读取功能
-- @usage manage.sleep("charge") -- 充电结束休眠
function manage.sleep(tag)
    assert(tag and tag ~= nil, "pm.sleep tag invalid")
    tags[tag] = 0  -- 减少唤醒计数

    -- 检查是否所有tag都已休眠
    for k, v in pairs(tags) do
        if v > 0 then  -- 还有唤醒的tag，不能休眠
            return
        end
    end

    -- 所有tag都已休眠，执行休眠操作
    logF("pm sleep", tag)
    pmFlag = true
    sys.publish("SYS_WAKE_STATUS", false)  -- 发布休眠状态事件
    pm.power(pm.WORK_MODE, 1)  -- 设置为长连接低功耗模式
end

-- 检查模块是否处于休眠状态
-- @return boolean true=休眠中，false=唤醒状态
function manage.isSleep()
    return pmFlag
end

-- 配置电源按键GPIO（GPIO 46），双边沿中断触发
-- @usage gpio.setup(46, pwrkeyCb, gpio.PULLUP, gpio.BOTH)
gpio.setup(46, pwrkeyCb, gpio.PULLUP, gpio.BOTH)

-- 关机事件处理
-- 订阅SYS_SHUTDOWN事件，执行关机流程
sys.subscribe("SYS_SHUTDOWN", function()
    mobile.flymode(0, true)  -- 进入飞行模式
    sys.timerStart(pm.shutdown, 1000)  -- 1秒后关机
end)

return manage
