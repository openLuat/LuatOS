--[[
@module  led_app
@summary LED 指示灯控制模块
@version 1.0.0
@date    2026.10.20
@usage
LED GPIO27（高电平点亮）。支持闪烁/常亮/熄灭。

消息协议（sys.publish/subscribe）：
  订阅:
    "led_blink_request"  → 闪烁 5 秒（亮 1s 灭 1s）
    "led_set_request"    → 直接控制 (value: 1=亮, 0=灭)
  发布:
    "led_status"         → 当前状态 ("on"/"off"/"blinking")
]]

local LED_PIN = 27
local led_status = "off"

local function led_blink_task()
    led_status = "blinking"
    sys.publish("led_status", "blinking")
    log.info("led_app", "开始闪烁")

    for i = 1, 5 do
        gpio.set(LED_PIN, 1)
        sys.wait(1000)
        gpio.set(LED_PIN, 0)
        sys.wait(1000)
    end

    led_status = "off"
    sys.publish("led_status", "off")
    log.info("led_app", "闪烁结束")
end

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

local function on_led_blink_request()
    if led_status == "blinking" then
        log.warn("led_app", "LED正在闪烁中，忽略请求")
        return
    end
    sys.taskInit(led_blink_task)
end

gpio.setup(LED_PIN, 0) -- 初始熄灭

sys.subscribe("led_blink_request", on_led_blink_request)
sys.subscribe("led_set_request", on_led_set_request)

log.info("led_app", "模块已加载，LED GPIO:", LED_PIN)
