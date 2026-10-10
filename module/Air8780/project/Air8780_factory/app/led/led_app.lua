--[[
@module  led_app
@summary LED指示灯控制应用模块
@version 1.0.0
@date    2026.09.10
@author  江访
@usage
LED控制模块，支持以下功能：
1. LED闪烁：亮1秒灭1秒，持续5秒（用于设备寻址或状态指示）
2. LED常亮：持续点亮（用于指示设备正常工作）
3. LED熄灭：持续熄灭（用于低功耗模式或关闭指示）

硬件配置：
- LED GPIO: GPIO27（高电平点亮，低电平熄灭）

消息协议（通过sys.publish/subsribe实现模块间通信）：
订阅:
- "led_blink_request"    → 启动LED闪烁5秒
- "led_set_request"      → 直接控制LED亮灭 (value: 1=亮, 0=灭)

发布:
- "led_status"           → LED当前状态 (value: "on"/"off"/"blinking")

使用示例：
    sys.publish("led_blink_request")      -- 启动闪烁
    sys.publish("led_set_request", 1)     -- 常亮
    sys.publish("led_set_request", 0)     -- 熄灭
]]

-- LED GPIO配置
local LED_PIN = 27

-- LED当前状态
local led_status = "off"

--[[
LED闪烁任务

@local
@function led_blink_task
@return nil
@usage
LED闪烁5秒，亮1秒灭1秒
]]
local function led_blink_task()
    led_status = "blinking"
    sys.publish("led_status", "blinking")
    log.info("led_app", "开始闪烁")

    for i = 1, 5 do
        gpio.set(LED_PIN, 1)  -- 亮
        sys.wait(1000)
        gpio.set(LED_PIN, 0)  -- 灭
        sys.wait(1000)
    end

    led_status = "off"
    sys.publish("led_status", "off")
    log.info("led_app", "闪烁结束")
end

--[[
LED设置事件处理

@local
@function on_led_set_request
@param value number 1=亮, 0=灭
]]
local function on_led_set_request(value)
    if value == 1 then
        gpio.set(LED_PIN, 1)
        led_status = "on"
        sys.publish("led_status", "on")
        log.info("led_app", "LED常亮")
    else
        gpio.set(LED_PIN, 0)
        led_status = "off"
        sys.publish("led_status", "off")
        log.info("led_app", "LED熄灭")
    end
end

--[[
LED闪烁请求处理

@local
@function on_led_blink_request
]]
local function on_led_blink_request()
    if led_status == "blinking" then
        log.warn("led_app", "LED正在闪烁中，忽略请求")
        return
    end
    sys.taskInit(led_blink_task)
end

-- 初始化LED GPIO
gpio.setup(LED_PIN, 0)  -- 初始熄灭

-- 订阅消息
sys.subscribe("led_blink_request", on_led_blink_request)
sys.subscribe("led_set_request", on_led_set_request)

log.info("led_app", "模块已加载，LED GPIO:", LED_PIN)
