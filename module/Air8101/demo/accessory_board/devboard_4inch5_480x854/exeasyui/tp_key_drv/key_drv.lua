--[[
@module  key_drv
@summary 按键驱动模块
@version 1.0
@date 2026.01.26
@author 江访
@usage
本文件为按键驱动功能模块，核心业务逻辑为：
1、初始化切换键和确认键的GPIO；
2、配置按键事件的中断处理函数；
3、实现按键防抖功能，防止误触发；
4、对外发布按键消息；

本文件的对外接口有1个：
1、key_drv.init()：初始化按键驱动；
]]

local key_drv = {}

-- 按键定义（Air8101开发板）
local key_switch = 33 -- GPIO33：切换/选择按键
local key_confirm = 34 -- GPIO34：确认/进入按键


-- 按键事件处理函数
local function handle_boot_key(val)
    if val == 1 then
        sys.publish("KEY_EVENT", "key1_down")
    end
end

local function handle_pwr_key(val)
    if val == 1 then
        sys.publish("KEY_EVENT", "key2_down")
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
    gpio.setup(key_switch, handle_boot_key, gpio.PULLDOWN, gpio.BOTH)
    gpio.debounce(key_switch, 200, 0) -- 防抖，防止频繁触发

    gpio.setup(key_confirm, handle_pwr_key, gpio.PULLDOWN, gpio.BOTH)
    gpio.debounce(key_confirm, 200, 0) -- 防抖，防止频繁触发

    log.info("key_drv", "按键初始化完成")
    return true
end

key_drv.init()
return key_drv