--演示airtalk基本功能
--按一次boot，开始1对1对讲，再按一次boot，结束对讲
--按一次powerkey，开始1对多对讲，再按一次powerkey或者boot，结束对讲
PROJECT = "airtalk_demo"
VERSION = "1.0.1"
PRODUCT_KEY = "s1uUnY6KA06ifIjcutm5oNbG3MZf5aUv" -- 到 iot.openluat.com 创建项目,获取正确的项目id
_G.sys=require"sys"
log.style(1)
require "demo_define"
require "airtalk_dev_ctrl"
require "audio_config"

--errDump.config(true, 600, "airtalk_test")
mcu.hardfault(0)
local function boot_key_cb()
    sys.sendMsg(USER_TASK_NAME, MSG_KEY_PRESS, false)
end

local function power_key_cb()
    sys.sendMsg(USER_TASK_NAME, MSG_KEY_PRESS, true)
end

--按下boot开始上传，再按下停止，加入了软件去抖，不需要长按了
gpio.setup(0, boot_key_cb, gpio.PULLDOWN, gpio.RISING)
gpio.debounce(0, 200, 1)
gpio.setup(gpio.PWR_KEY, power_key_cb, gpio.PULLUP, gpio.FALLING)
gpio.debounce(gpio.PWR_KEY, 200, 1)

local test_ready = false
local function task_cb(msg)
    log.info("未处理消息", msg[1], msg[2], msg[3], msg[4])
    if msg[1] == MSG_SPEECH_IND then

    elseif msg[1] == MSG_NOT_READY then
        test_ready = false
        msg = sys.waitMsg(USER_TASK_NAME, MSG_KEY_PRESS)
    end
end

local function user_task()
    audio_init()
    airtalk_mqtt_init()
    local msg
    while true do
        msg = sys.waitMsg(USER_TASK_NAME, MSG_KEY_PRESS)
        if msg[2] then  -- true powerkey false boot key
            sys.sendMsg(AIRTALK_TASK_NAME, MSG_GROUP_SPEECH_TEST_START)   --测试阶段自动给一个device打
        else
            sys.sendMsg(AIRTALK_TASK_NAME, MSG_PERSON_SPEECH_TEST_START)   --测试阶段自动给一个device打
        end 
        msg = sys.waitMsg(USER_TASK_NAME, MSG_KEY_PRESS)
        sys.sendMsg(AIRTALK_TASK_NAME, MSG_SPEECH_STOP_TEST_END)        --再按一次就自动挂断
    end
end

sys.taskInitEx(user_task, USER_TASK_NAME, task_cb)

--定期检查ram使用情况，及时发现内存泄露
sys.taskInit(function()
    while true do
        sys.wait(60000)
        log.info("time", os.time())
        log.info("lua", rtos.meminfo("lua"))
        log.info("sys", rtos.meminfo("sys"))
        log.info("psram", rtos.meminfo("psram"))
    end
end)
sys.run()