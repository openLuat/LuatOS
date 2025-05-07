--[[
1. 本demo可直接在Air8000整机开发板上运行，如有需要请luat.taobao.com 购买
2. 使用了如下管脚
       [54, "GPIO146", " PIN54脚, 用于控制网络灯"],
3. 本程序使用逻辑：
3.1. led(红灯)，1秒间隔闪烁
]]

local taskName ="task_led"
local led = 146   -- 板载LED 灯

local function gpio_setup()
    gpio.setup(led, 1) -- GPIO2打开给camera电源供电
end

local function led_det_task()
    gpio_setup()
    while true do
        log.info("led", "闪烁led")
        gpio.toggle(led)
        sys.wait(1000)
    end
end


sysplus.taskInitEx(led_det_task, taskName)   
