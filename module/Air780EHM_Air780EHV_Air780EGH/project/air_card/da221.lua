-- TODO 长时间不移动，关闭定位，上传最后一次定位成功的地址
exvib = require("exvib")

local intPin = gpio.WAKEUP0 -- 中断检测脚，内部固定wakeup0
local tid -- 获取定时打开的定时器id
local num = 0 -- 计数器 
local ticktable = {0, 0, 0, 0, 0} -- 存放5次中断的tick值，用于做有效震动对比
local eff = false -- 有效震动标志位，用于判断是否触发定位

-- 设备状态
device_status = {is_moving = 0, is_standby = 1}

cur_status = device_status.is_moving

local vib_is_moving = 0
-- 检测10秒内震动次数
local function check_is_moving()
    while true do
    for i = 1, 10 do sys.wait(1000) end
    if vib_is_moving >= 5 then 
        cur_status = device_status.is_moving 
    end
    vib_is_moving = 0
    end
end

local vib_is_standby = 0
-- 检测60秒内震动次数
local function check_is_standby()
    while true do
    for i = 1, 60 do sys.wait(1000) end
    if vib_is_standby < 3 then 
        cur_status = device_status.is_standby 
    end
    vib_is_standby = 0
    end
end

sys.taskInit(check_is_standby)
sys.taskInit(check_is_moving)

-- 持续震动模式中断函数
local function ind()
    log.info("int", gpio.get(intPin))
    vib_is_moving = vib_is_moving + 1
    vib_is_standby = vib_is_standby + 1
    -- 上升沿为触发震动中断
    if gpio.get(intPin) == 1 then
        local x, y, z = exvib.read_xyz() -- 读取x，y，z轴的数据
        log.info("x", x .. 'g', "y", y .. 'g', "z", z .. 'g')
    end
end

local function vib_fnc()
    gpio.setup(20, 1)
    sys.wait(1000)
    -- 1，微小震动检测，用于检测轻微震动的场景，例如用手敲击桌面；加速度量程2g；
    -- 2，运动检测，用于电动车或汽车行驶时的检测和人行走和跑步时的检测；加速度量程4g；
    -- 3，跌倒检测，用于人或物体瞬间跌倒时的检测；加速度量程8g；
    -- 打开震动检测功能
    exvib.open(2)
    -- 设置gpio防抖100ms
    gpio.debounce(intPin, 100)
    -- 设置gpio中断触发方式wakeup2唤醒脚默认为双边沿触发
    gpio.setup(intPin, ind)
    while true do
        sys.wait(1000)
        log.info("cur_status",cur_status,"vib_is_moving",vib_is_moving,"vib_is_standby",vib_is_standby)
        if cur_status == device_status.is_moving then
            local mode = config.UPLOAD_CONFIG.locateType
            if mode == 0 then
                if gpio_util.get_recording_mode() then
                    -- 开启室内+卫星定位
                    gps.open()
                    lbs_util.open()
                else
                    -- 关闭室内+卫星定位
                    gps.close()
                    lbs_util.close()
                end
            elseif mode == 1 then
                if gpio_util.get_recording_mode() then
                    -- 开启卫星定位
                    lbs_util.open()
                    gps.open()
                else
                    -- 关闭卫星定位
                    gps.close()
                end
            elseif mode == 2 then
                -- 开启室内+卫星定位
                gps.open()
                lbs_util.open()
            end
        else
            gps.close()
        end
    end
end

sys.taskInit(vib_fnc)
