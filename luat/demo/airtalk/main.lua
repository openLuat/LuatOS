PROJECT = "airtalk_demo"
VERSION = "1.0.0"
require "airtalk_demo"
local uplink = false
local function key_cb()
    if uplink then
        uplink = false
    else
        uplink = true
    end
    log.info("uplink", uplink)
    airtalk.uplink(uplink)
end

--按下boot开始上传，再按下停止，加入了软件去抖，不需要长按了
gpio.setup(0, key_cb, gpio.PULLDOWN, gpio.RISING)
gpio.debounce(0, 200, 1)
--开始演示airtalk，并且修改对应的topic，如果留空，则其他人也能听到了
sys.taskInit(airtalk_demo_mqtt_8k, "改成自己的topic")
--定期检查ram使用情况，及时发现内存泄露
sys.taskInit(function()
    while true do
        sys.wait(5000)
        log.info("time", os.time())
        log.info("lua", rtos.meminfo("lua"))
        log.info("sys", rtos.meminfo("sys"))
        log.info("psram", rtos.meminfo("psram"))
    end
end)

sys.run()