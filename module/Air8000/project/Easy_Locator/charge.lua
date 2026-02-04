--[[
@module  charge
@summary 电池管理模块：电量检测、充电状态管理、低电量保护
@version 1.0
@author  Auto
@usage
本模块实现以下功能：
1. 电池电压实时监测
2. 电池电量百分比计算（基于放电曲线）
3. 充电状态检测（GPIO中断触发）
4. 低电量保护（低于30%且未充电，2分钟后关机）
5. 充电LED指示灯控制
]]

local charge = {}

-- ==================== 全局变量 ====================

-- 当前电池电压（mV）
local vbat = 0

-- 电池电量百分比（0-100）
local batteryPercent = 50

-- 是否正在充电
local isCharge = false

-- 连续低电量次数（用于低电量保护）
-- 需要连续检测到2次低电量才触发关机，避免误判
local LOW_BATTERY_TIME = 0

-- ADC校准偏移值（mV）
local ADC_DELTA = 10

-- 电压平均值计算窗口大小
local AVR_MAX = 15

-- 电压历史缓存（用于计算平均值）
local nochg_t = {}

-- 充电状态指示LED（GPIO 21 红色）
--GPIO17 绿色 GPIO20 蓝色
--Air8000A开发板上有三个灯 分别是GPIO 17/20/21 这里是随便选了一个 用户可以自己根据项目自行修改
local pwrLed = gpio.setup(21, 0)

-- ==================== 电池放电曲线 ====================

-- 电池电压-电量对应表（单位：mV）
-- 从100%到0%的电压值，用于根据电压计算电量百分比
-- 修改了前8个点确保满电时显示100%不跳动
local battery = {
    4120, 4105, 4090, 4075, 4062, 4055, 4045, 4040,  -- 100%-99%
    4031, 4019, 4007, 3995, 3984, 3971, 3960, 3947,  -- 98%-91%
    3936, 3924, 3913, 3901, 3890, 3878, 3866, 3856,  -- 90%-83%
    3845, 3834, 3823, 3812, 3801, 3790, 3781, 3769,  -- 82%-75%
    3758, 3749, 3738, 3728, 3718, 3708, 3699, 3688,  -- 74%-67%
    3679, 3671, 3661, 3652, 3644, 3636, 3628, 3620,  -- 66%-59%
    3613, 3605, 3599, 3592, 3585, 3579, 3573, 3568,  -- 58%-51%
    3562, 3557, 3552, 3547, 3542, 3537, 3532, 3527,  -- 50%-43%
    3523, 3519, 3515, 3510, 3505, 3501, 3497, 3492,  -- 42%-35%
    3488, 3484, 3479, 3475, 3470, 3466, 3461, 3457,  -- 34%-27%
    3452, 3447, 3442, 3436, 3431, 3425, 3420, 3414,  -- 26%-19%
    3408, 3401, 3394, 3387, 3379, 3371, 3362, 3352,  -- 18%-11%
    3341, 3327, 3312, 3294  -- 10%-7%（低于3269mV为0%）
}

-- ==================== 内部函数 ====================

local vbus_number =gpio.WAKEUP1
-- GPIO中断回调：充电状态检测
-- 通过VBUS检测充电状态（高电平=充电中，低电平=未充电）
--
-- @usage gpio.setup(vbus_number, chargeCheck, gpio.PULLDOWN, gpio.BOTH)
local function chargeCheck()
    -- 检测充电状态
    if gpio.get(vbus_number) == 0 then
        -- 未充电
        if isCharge then
            -- pm.power(pm.USB, false)  -- 关闭USB电源（可选）
            isCharge = false
            pwrLed(0)  -- 关闭充电LED
            manage.sleep("charge")  -- 休眠charge模块
        end
    else
        -- 充电中
        if not isCharge then
            -- pm.power(pm.USB, true)  -- 打开USB电源（可选）
            isCharge = true
            manage.wake("charge")  -- 唤醒charge模块
            pwrLed(1)  -- 打开充电LED
        end
    end
end

-- 通过当前电压推算电量百分比
-- @return number 电池电量百分比（0-100）
local function mathBatteryPercent()
    if vbat >= battery[1] then
        return 100  -- 满电
    end
    if vbat <= battery[#battery] then
        return 0   -- 没电
    end

    -- 线性插值计算电量
    for i = 1, #battery do
        if vbat <= battery[i] and vbat > battery[i + 1] then
            return (100 - i)
        end
    end
end

-- 电压平均值计算（滑动窗口）
-- @param number v 新的电压值（mV）
-- @return number 平均电压值（mV）
local function append_vadc(v)
    -- 维护滑动窗口大小为AVR_MAX（15个点）
    if #nochg_t >= AVR_MAX then
        table.insert(nochg_t, v)
        table.remove(nochg_t, 1)  -- 移除最旧的值
    else
        -- 初始化时填充窗口
        while #nochg_t < AVR_MAX do
            table.insert(nochg_t, v)
        end
    end

    -- 计算平均值
    local totv = 0
    for i = 1, #nochg_t do
        totv = totv + nochg_t[i]
    end
    return totv // #nochg_t  -- 整数除法
end

-- 电池电量周期性检测函数
-- 功能：
-- 1. 读取ADC电压值
-- 2. 计算平均电压
-- 3. 计算电量百分比
-- 4. 低电量保护：低于30%且未充电，连续2次检测后关机
-- @usage checkBattery() -- 在定时器中周期调用
local function checkBattery()
    adc.open(adc.CH_VBAT)  -- 打开ADC通道
    local _, tmp = adc.read(adc.CH_VBAT)  -- 读取电压
    vbat = tmp + ADC_DELTA  -- 调整电压值（校准）
    adc.close(adc.CH_VBAT)  -- 关闭ADC通道

    vbat = append_vadc(vbat)  -- 计算平均电压

    batteryPercent = mathBatteryPercent()  -- 计算电池百分比

    -- 低电量保护逻辑
    if batteryPercent <= 30 and not isCharge then
        LOW_BATTERY_TIME = LOW_BATTERY_TIME + 1
        -- 连续检测到2次低电量，触发关机
        if LOW_BATTERY_TIME > 1 then
            manage.powerOff()  -- 关机
        end
    else
        -- 恢复低电量计数
        if LOW_BATTERY_TIME > 0 then
            LOW_BATTERY_TIME = LOW_BATTERY_TIME - 1
        end
    end
end

-- ==================== 导出函数 ====================

-- 获取当前电池电压
-- @return number 电池电压（mV）
function charge.getVbat()
    return vbat
end

-- 获取当前电池电量百分比
-- @return number 电量百分比（0-100）
function charge.getBatteryPercent()
    return batteryPercent
end

-- 获取充电状态
-- @return boolean true=充电中，false=未充电
function charge.isCharge()
    return isCharge
end

-- ==================== 初始化 ====================

-- 配置充电检测(vbus管脚)，双边沿中断触发
gpio.setup(vbus_number, chargeCheck, gpio.PULLDOWN, gpio.BOTH)
chargeCheck()  -- 初始检测一次

-- 电池检测任务
-- 1. 开机后如果是充电状态，等待6秒再开始检测（避免误报）
-- 2. 连续采集10次电压作为初始均值（稳定电路）
-- 3. 之后每60秒检测一次电池电量
sys.taskInit(function()
    local st_ost = os.time()
    -- 充电状态下，开机前6秒不上报
    while isCharge and (os.time() - st_ost) < 6 do
        sys.wait(1000)
    end

    -- 连续采集10次电压，作为初始均值成员（稳定ADC电路）
    for i = 1, AVR_MAX do
        checkBattery()
        sys.wait(200)
    end

    -- 正常周期：每60秒检测一次电池电量
    while true do
        checkBattery()
        sys.wait(60000)
    end
end)

return charge