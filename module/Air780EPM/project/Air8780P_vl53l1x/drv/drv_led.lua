--[[
@module  drv_led
@summary LED指示灯驱动配置功能模块
@version 1.0
@date    2026.07.23
@author  江访
@usage
本文件为LED指示灯驱动配置功能模块，提供了LED灯在正常工作状态和PSM+休眠状态下的控制逻辑。

LED状态说明：
1、正常工作状态（LED点亮）：设备初始化完成、数据采集中、网络通信中
2、PSM+模式（LED熄灭）：进入深度休眠前关闭，降低功耗

本文件的对外接口有2个：
1、sys.subscribe("LED_SET_HIGH", led_set_high_func)：拉高LED指示灯
2、sys.subscribe("LED_SET_LOW", led_set_low_func)：拉低LED指示灯

其他模块通过 sys.publish 控制LED：
    sys.publish("LED_SET_HIGH", gpio_led)  -- 拉高LED
    sys.publish("LED_SET_LOW", gpio_led)   -- 拉低LED
]]

-- ==================== LED拉高事件处理 ====================

--[[
LED拉高事件处理函数

订阅LED_SET_HIGH消息，收到后拉高指定GPIO引脚。
LED点亮表示设备处于正常工作状态。

@param number gpio_led GPIO引脚号（例如27）
]]
local function led_set_high_func(gpio_led)
    if not gpio_led then return end
    gpio.setup(gpio_led, 1)
    gpio.set(gpio_led, 1)
    log.info("drv_led", "GPIO" .. gpio_led .. " 拉高")
end

-- ==================== LED拉低事件处理 ====================

--[[
LED拉低事件处理函数

订阅LED_SET_LOW消息，收到后拉低指定GPIO引脚。
LED熄灭表示设备即将进入低功耗模式。

@param number gpio_led GPIO引脚号（例如27）
]]
local function led_set_low_func(gpio_led)
    if not gpio_led then return end
    gpio.set(gpio_led, 0)
    log.info("drv_led", "GPIO" .. gpio_led .. " 拉低")
end

-- ==================== 事件订阅 ====================

sys.subscribe("LED_SET_HIGH", led_set_high_func)
sys.subscribe("LED_SET_LOW", led_set_low_func)

log.info("drv_led", "模块已加载，等待LED_SET_HIGH/LED_SET_LOW消息")

-- 如果项目启动后需要LED保持某种状态，直接在此处配置初始状态
-- 此处的配置取决于硬件设计，合宙核心板上电后GPIO默认状态为高阻态
