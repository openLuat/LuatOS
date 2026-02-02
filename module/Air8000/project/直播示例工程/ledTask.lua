--[[
@module  ledTask
@summary LED指示灯控制模块
@version 1.0
@author  Auto
@usage
本模块实现以下功能：
1. 蓝灯：网络状态指示（已注释）
2. 黄灯：GNSS定位状态指示（已注释）
3. 红灯：充电状态指示（由charge.lua控制）
注意：当前项目LED功能已全部注释，实际未使用
]]

-- ==================== 蓝灯（网络状态指示） ====================

--[[
蓝灯GPIO配置（GPIO 1）
功能：网络状态指示
- 闪烁：网络未连接
- 常灭：网络已连接

状态：已注释，当前未使用
]]
-- local netLed = gpio.setup(1, 0)

--[[
网络状态指示灯任务
当网络未连接时，蓝灯以500ms间隔闪烁
当网络已连接时，蓝灯熄灭

状态：已注释，当前未使用
]]
-- sys.taskInit(function()
--     while true do
--         -- 网络未连接：蓝灯闪烁
--         while not srvs.isConnected() do
--             manage.wake("led")
--             netLed(1)
--             sys.wait(500)
--             netLed(0)
--             manage.sleep("led")
--             sys.wait(500)
--         end
--         -- 网络已连接：蓝灯熄灭
--         netLed(0)
--         while srvs.isConnected() do
--             sys.wait(10000)
--         end
--     end
-- end)

-- ==================== 黄灯（GNSS定位状态指示） ====================

--[[
黄灯GPIO配置
功能：GNSS定位状态指示
- 常亮：已定位
- 闪烁：未定位

说明：
在当前Air8000A模块上，由GNSS芯片的1PPS引脚控制
可以通过向GNSS芯片发送指令改变1PPS输出周期

状态：已注释，当前未使用
]]
-- local gnssLed = gpio.setup(xxx, 0)

--[[
GNSS定位状态指示灯任务
当已定位时，黄灯常亮
当未定位时，黄灯以500ms间隔闪烁

状态：已注释，当前未使用
]]
-- sys.taskInit(function()
--     while true do
--         if gnss.isFix() then
--             -- 已定位：黄灯常亮
--             gnssLed(1)
--             sys.wait(1000)
--         else
--             -- 未定位：黄灯闪烁
--             gnssLed(0)
--             sys.wait(500)
--             gnssLed(0)
--             sys.wait(500)
--         end
--     end
-- end)

-- ==================== 红灯（充电状态指示） ====================

--[[
红灯GPIO配置
功能：充电状态指示
- 常亮：正在充电
- 熄灭：未充电

说明：红灯控制已移至charge.lua模块
- GPIO：16
- 控制逻辑：根据充电状态（GPIO 40）自动控制

状态：已注释，当前由charge.lua控制
]]
-- local chargeLed = gpio.setup(xxx, 0)

--[[
充电状态指示灯任务
根据充电状态控制红灯

状态：已注释，当前由charge.lua控制
]]
-- sys.taskInit(function()
--     while true do
--         chargeLed(xxx.isCharge() and 1 or 0)
--         sys.wait(1000)
--     end
-- end)