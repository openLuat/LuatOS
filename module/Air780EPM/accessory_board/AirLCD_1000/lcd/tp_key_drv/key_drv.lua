--[[
@module  key_drv
@summary 按键驱动模块，管理BOOT键和PWR键的GPIO中断处理
@version 1.0
@date    2025.12.8
@author  江访
@usage
本文件为按键驱动功能模块，核心业务逻辑为：
1、初始化BOOT键(GPIO0)和PWR键(gpio.PWR_KEY)的GPIO引脚；
2、配置按键事件的GPIO中断处理函数，支持上升沿和下降沿触发；
3、实现50ms防抖功能，防止抖动误触发；
4、对外发布按键消息"KEY_EVENT"，包含按键类型和状态信息；

本文件的对外接口有1个：
1、key_drv.init()：初始化按键驱动，配置GPIO中断和防抖参数；
]]

local key_drv = {}

-- 按键定义
local key_boot = 0           -- GPIO0按键（BOOT键）
local key_pwr = gpio.PWR_KEY -- 电源按键


-- 按键事件处理函数
local function handle_boot_key(val)
    -- print("key_boot", val)
    if val == 1 then
        sys.publish("KEY_EVENT", "boot_down")
    else
        sys.publish("KEY_EVENT", "boot_up")
    end
end

local function handle_pwr_key(val)
    -- print("key_pwr", val)
    if val == 1 then
        sys.publish("KEY_EVENT", "pwr_up")
    else
        sys.publish("KEY_EVENT", "pwr_down")
    end
end

--[[
初始化按键GPIO；
配置BOOT键和PWR键的GPIO中断；

@api key_drv.init()
@summary 配置BOOT键和PWR键的GPIO中断
@return bool 初始化只会返回true

@usage
local result = key_drv.init()
if result then
    log.info("按键驱动初始化成功")
end
]]
function key_drv.init()
    gpio.setup(key_boot, handle_boot_key, gpio.PULLDOWN, gpio.BOTH)
    gpio.debounce(key_boot, 50, 0)     -- 防抖，防止频繁触发

    gpio.setup(key_pwr, handle_pwr_key, gpio.PULLUP, gpio.BOTH)
    gpio.debounce(key_pwr, 50, 0)     -- 防抖，防止频繁触发

    log.info("key_drv", "按键初始化完成")
    return true
end

key_drv.init()
return key_drv