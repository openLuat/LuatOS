--[[
@module  charger_app
@summary 充电桩业务逻辑应用模块，处理充电状态、充电数据和控制逻辑
@version 1.0
@date    2026.04.08
@author  LuatOS查询路由代理
]]

-- 充电状态常量
local STATUS_IDLE = 0
local STATUS_CHARGING = 1
local STATUS_PAUSED = 2
local STATUS_FINISHED = 3

-- 充电桩状态变量
local charging_status = STATUS_IDLE
local battery_level = 0
local charging_amount = 0
local charging_time = 0
local remaining_time = 0
local charging_power = 0

-- 充电任务
local charging_task = nil

-- 模块定义
local module = {
    STATUS_IDLE = STATUS_IDLE,
    STATUS_CHARGING = STATUS_CHARGING,
    STATUS_PAUSED = STATUS_PAUSED,
    STATUS_FINISHED = STATUS_FINISHED
}

-- 获取充电状态
function module.get_status()
    return charging_status
end

-- 获取电池电量
function module.get_battery_level()
    return battery_level
end

-- 获取充电电量
function module.get_charging_amount()
    return charging_amount
end

-- 获取充电时间
function module.get_charging_time()
    return charging_time
end

-- 获取剩余时间
function module.get_remaining_time()
    return remaining_time
end

-- 获取充电功率
function module.get_charging_power()
    return charging_power
end

-- 模拟电池电量更新
local function update_battery_level()
    if charging_status == STATUS_CHARGING then
        -- 假设电池容量为70kWh，充电功率为7kW
        local battery_capacity = 70 -- kWh
        local charging_power_rate = 7 -- kW
        
        -- 每分钟充电电量增加
        local charging_amount_increment = charging_power_rate / 60 -- kWh/分钟
        charging_amount = charging_amount + charging_amount_increment
        
        -- 计算电池电量百分比
        battery_level = (charging_amount / battery_capacity) * 100
        battery_level = math.min(battery_level, 100)
    end
end

-- 模拟充电数据更新
local function update_charging_data()
    if charging_status == STATUS_CHARGING then
        -- 假设充电功率为7kW
        local power = 7 -- kW
        local time_in_hours = 1/60 -- 1分钟
        
        charging_amount = charging_amount + (power * time_in_hours)
        charging_time = charging_time + 1
        
        -- 计算剩余时间
        local remaining_capacity = (100 - battery_level) * 0.01 * 70 -- 假设电池容量为70kWh
        local current_power = power -- kW
        remaining_time = math.floor(remaining_capacity / current_power * 60) -- 转换为分钟
        
        charging_power = power
    end
end

-- 充电任务函数
local function charging_task_func()
    while true do
        sys.wait(60000) -- 每分钟更新一次
        
        if charging_status == STATUS_CHARGING then
            update_battery_level()
            update_charging_data()
            
            -- 检查充电是否完成
            if battery_level >= 100 then
                charging_status = STATUS_FINISHED
                sys.publish("CHARGING_FINISHED")
            end
        end
    end
end

-- 开始充电
function module.start_charging()
    if charging_status == STATUS_IDLE or charging_status == STATUS_PAUSED then
        charging_status = STATUS_CHARGING
        
        -- 如果充电任务未启动，创建充电任务
        if not charging_task then
            charging_task = sys.taskInit(charging_task_func)
        end
        
        sys.publish("CHARGING_STARTED")
        return true
    end
    
    return false
end

-- 暂停充电
function module.pause_charging()
    if charging_status == STATUS_CHARGING then
        charging_status = STATUS_PAUSED
        sys.publish("CHARGING_PAUSED")
        return true
    end
    
    return false
end

-- 停止充电
function module.stop_charging()
    if charging_status ~= STATUS_IDLE then
        charging_status = STATUS_IDLE
        
        -- 重置充电数据
        battery_level = 0
        charging_amount = 0
        charging_time = 0
        remaining_time = 0
        charging_power = 0
        
        sys.publish("CHARGING_STOPPED")
        return true
    end
    
    return false
end

-- 重置充电状态
function module.reset_charging()
    module.stop_charging()
end

-- 初始化充电桩应用
local function init()
    -- 初始化状态
    charging_status = STATUS_IDLE
    battery_level = 0
    charging_amount = 0
    charging_time = 0
    remaining_time = 0
    charging_power = 0
end

-- 启动应用
local function start()
    init()
end

-- 停止应用
local function stop()
    if charging_task then
        charging_task = nil
    end
end

-- 导出启动和停止函数
module.start = start
module.stop = stop

-- 应用生命周期事件
sys.subscribe("APP_START", start)
sys.subscribe("APP_STOP", stop)

return module
