PROJECT = "airtalk_demo"
VERSION = "1.0.0"
require "airtalk_net_ctrl.lua"

AIRTALK_TASK_NAME = "airtalk_task"

airtalk_mqtt_init()
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