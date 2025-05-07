local charge = {}
-- 当前vbat电压
local vbat = 0
-- 电池电量百分比
local batteryPercent = 50
-- 是否正在充电
local isCharge = false
-- 连续低电量次数
local LOW_BATTERY_TIME = 0
local ADC_DELTA = 65
local AVR_MAX = 15
local nochg_t = {}

-- 红灯
local pwrLed = gpio.setup(16, 0, nil, nil, 4)

-- 电池放电曲线
-- local battery = {4175, 4128, 4108, 4093, 4079, 4067, 4055, 4043, 4031, 4019, 4007, 3995, 3984, 3971, 3960, 3947, 3936, 3924, 3913, 3901, 3890, 3878, 3866, 3856, 3845, 3834, 3823, 3812, 3801, 3790, 3781, 3769, 3758, 3749, 3738, 3728, 3718, 3708, 3699, 3688, 3679, 3671, 3661, 3652, 3644, 3636, 3628,
--                  3620, 3613, 3605, 3599, 3592, 3585, 3579, 3573, 3568, 3562, 3557, 3552, 3547, 3542, 3537, 3532, 3527, 3523, 3519, 3515, 3510, 3505, 3501, 3497, 3492, 3488, 3484, 3479, 3475, 3470, 3466, 3461, 3457, 3452, 3447, 3442, 3436, 3431, 3425, 3420, 3414, 3408, 3401, 3394, 3387, 3379, 3371,
--                  3362, 3352, 3341, 3327, 3312, 3294, 3269}

-- 改了前面八个确保有100% 不跳动
local battery = {4120, 4105, 4090, 4075, 4062, 4055, 4045, 4040, 4031, 4019, 4007, 3995, 3984, 3971, 3960, 3947, 3936, 3924, 3913, 3901, 3890, 3878, 3866, 3856, 3845, 3834, 3823, 3812, 3801, 3790, 3781, 3769, 3758, 3749, 3738, 3728, 3718, 3708, 3699, 3688, 3679, 3671, 3661, 3652, 3644, 3636, 3628,
                 3620, 3613, 3605, 3599, 3592, 3585, 3579, 3573, 3568, 3562, 3557, 3552, 3547, 3542, 3537, 3532, 3527, 3523, 3519, 3515, 3510, 3505, 3501, 3497, 3492, 3488, 3484, 3479, 3475, 3470, 3466, 3461, 3457, 3452, 3447, 3442, 3436, 3431, 3425, 3420, 3414, 3408, 3401, 3394, 3387, 3379, 3371,
                 3362, 3352, 3341, 3327, 3312, 3294, 3269}


-- gpio中断回调
local function chargeCheck()
    -- 检测充电状态
    if gpio.get(40) == 0 then
        if isCharge then
            -- pm.power(pm.USB, false)
            isCharge = false
            pwrLed(0)
            manage.sleep("charge")
        end
    else
        if not isCharge then
            -- pm.power(pm.USB, true)
            isCharge = true
            manage.wake("charge")
            pwrLed(1)
        end
    end
end



-- 通过当前电压推算电量百分比
local function mathBatteryPercent()
    if vbat >= battery[1] then
        return 100
    end
    if vbat <= battery[#battery] then
        return 0
    end
    for i = 1, #battery do
        if vbat <= battery[i] and vbat > battery[i + 1] then
            return (100 - i)
        end
    end
end

local function append_vadc(v)
    if #nochg_t >= AVR_MAX then
        table.insert(nochg_t, v)
        table.remove(nochg_t, 1)
    else
        while #nochg_t < AVR_MAX do
            table.insert(nochg_t, v)
        end
    end
    local totv = 0
    for i = 1, #nochg_t do
        totv = totv + nochg_t[i]
    end
    return totv // #nochg_t
end

-- 电池电量周期性更新，60s更新一次，且如果电量低于30%，并且2分钟没有插入电源，则关机


local function set_charge_en(en)
    local result = nil
    local gpio_pin = pcb.chargeCmdPin() -- 获取这个gpio,它在开机的是时候已经在2712A里面初始化过
    if en then
        -- log.info("+++++en  true  a8")
        result = sensor.yhm27xx(gpio_pin, 0x04, 0x02, 0xA8)
    else
        -- log.info("+++++en  false f8")
        result = sensor.yhm27xx(gpio_pin, 0x04, 0x02, 0xF8)
    end
    if result == true then
        -- log.info("yhm27xxx charge en", en, "写入成功")
    else
        -- log.info("yhm27xxx charge en", en, "写入失败")
    end
    -- 跟随打开
    result = sensor.yhm27xx(gpio_pin, 0x04, 0x01, 02)
    if result == true then
        -- log.info("yhm27xxx track", en, "写入成功")
    else
        -- log.info("yhm27xxx track", en, "写入失败")
    end
end

local function checkBattery()
    local flag_en_again = false
    if isCharge then
        -- set_charge_en(false)
        flag_en_again = true
        sys.wait(50)
    end

    adc.open(adc.CH_VBAT) -- 打开ADC通道
    local _, tmp = adc.read(adc.CH_VBAT) -- 读取电压
    vbat = tmp + ADC_DELTA -- 调整电压值 
    adc.close(adc.CH_VBAT) -- 关闭ADC通道
    if flag_en_again then
        vbat = vbat - 200 -- 0.2V 实测管子压降 
        -- set_charge_en(true)
    end
    local nowadc = vbat

    vbat = append_vadc(vbat)

    batteryPercent = mathBatteryPercent() -- 计算电池百分比
    if batteryPercent <= 30 and not isCharge then
        LOW_BATTERY_TIME = LOW_BATTERY_TIME + 1
        if LOW_BATTERY_TIME > 1 then
            manage.powerOff() -- 关机
        end
    else
        if LOW_BATTERY_TIME > 0 then
            LOW_BATTERY_TIME = LOW_BATTERY_TIME - 1
        end
    end
end


-- 获取当前电量
function charge.getVbat()
    return vbat
end


-- 获取当前电量百分比
function charge.getBatteryPercent()
    return batteryPercent
end

-- 获取充电状态
function charge.isCharge()
    return isCharge
end

gpio.setup(40, chargeCheck, gpio.PULLDOWN, gpio.BOTH)
chargeCheck()

sys.taskInit(function()
    local st_ost = os.time()
    while isCharge and (os.time() - st_ost) < 6 do
        sys.wait(1000) -- 开机后，前面10S 不要上报
    end
    -- 连续ADC 电路稳定后，连续采集10次作为初始均值成员
    for i = 1, AVR_MAX do
        checkBattery()
        sys.wait(200)
    end
    -- 后面正常获取ADC值，替代LOOPTIMER
    while true do
        checkBattery()
        sys.wait(60000)
    end
end)
return charge