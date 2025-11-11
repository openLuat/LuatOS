--[[
@module  agpio_task
@summary Air8000演示agpio功能模块
@version 1.0
@date    2025.10.21
@author  拓毅恒
@usage
本文件为Air8000开发板演示 AGPIO 功能的代码示例，核心业务逻辑为：
AGPIO与普通GPIO在PSM+模式下的区别演示
1. 初始化普通GPIO和AGPIO
   - 配置普通GPIO1为输出模式并设置为高电平
   - 配置AGPIO21为输出模式并设置为高电平
2. 等待一段时间让GPIO状态稳定
3. 关闭USB电源以降低功耗
4. 进入深度休眠模式（PSM+模式），此时RAM 掉电，唤醒后程序从初始状态运行。
5. 观察结果：通过示波器或逻辑分析仪等设备观察进入PSM+模式后普通GPIO为掉电状态，而AGPIO保持了休眠前的电平状态
]]

local gpio_number = 1   -- 普通GPIO GPIO号为1，休眠后掉电。
local Agpio_number = 21 -- AGPIO GPIO号为21，休眠后可保持电平。

gpio.setup(gpio_number, 1)
gpio.setup(Agpio_number, 1)

local function enterlowpower()
    sys.wait(10000)
    -- 关闭USB电源
    pm.power(pm.USB, false)
    -- 进入PSM+模式
    pm.power(pm.WORK_MODE, 3)
end

sys.taskInit(enterlowpower)
