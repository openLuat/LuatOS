--演示airtalk基本功能
--按一次boot，开始1对1对讲，再按一次boot，结束对讲
--按一次powerkey，开始1对多对讲，再按一次powerkey或者boot，结束对讲
PROJECT = "airtalk_demo"
VERSION = "1.0.1"
PRODUCT_KEY = "29uptfBkJMwFC7x7QeW10UPO3LecPYFu" -- 到 iot.openluat.com 创建项目,获取正确的项目id
_G.sys=require"sys"
log.style(1)
extalk = require("extalk")
exaudio = require("exaudio")
local USER_TASK_NAME = "user"
local MSG_READY = 10
local MSG_NOT_READY = 11
local MSG_KEY_PRESS = 12
local g_dev_list
-- 音频初始化设置参数,exaudio.setup 传入参数
local audio_setup_param ={
    model= "es8311",          -- 音频编解码类型,可填入"es8311","es8211"
    i2c_id = 0,          -- i2c_id,可填入0，1 并使用pins 工具配置对应的管脚
    pa_ctrl = 162,         -- 音频放大器电源控制管脚
    dac_ctrl = 164,        --  音频编解码芯片电源控制管脚    
}


local function contact_list(dev_list)
    g_dev_list = dev_list
    for i=1,#dev_list do
        log.info("联系人ID:",dev_list[i]["id"],"名称:",dev_list[i]["name"])
    end
end

local function state(event_table)
    if event_table.state  == extalk.START then
        log.info("对讲开始，可以说话了")
    elseif  event_table.state  == extalk.STOP then
        log.info("对讲结束")
    elseif  event_table.state  == extalk.UNRESPONSIVE then
        log.info("对端未响应")
    elseif  event_table.state  == extalk.ONE_ON_ONE then
        for i=1,#g_dev_list do
            if g_dev_list[i]["id"] == event_table.id then
                log.info(g_dev_list[i]["name"],",来电话了")
                break
            end
        end
    elseif  event_table.state  == extalk.BROADCAST then
        for i=1,#g_dev_list do
            if g_dev_list[i]["id"] == event_table.id then
                log.info(g_dev_list[i]["name"],"开始广播")
                break
            end
        end
    end
end

local extalk_configs = {
    key = PRODUCT_KEY,               -- 项目key，一般来说需要和main 的PRODUCT_KEY保持一致
    heart_break_time = 120,  -- 心跳间隔(单位秒)
    contact_list_cbfnc = contact_list, -- 联系人回调函数，回调信息含设备号和昵称
    state_cbfnc = state,  --状态回调，分为对讲开始，对讲结束，未响应
}

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
    local msg,res
    if exaudio.setup(audio_setup_param) then      --  音频初始化
        extalk.setup(extalk_configs)              -- airtalk 初始化
        while true do
            msg = sys.waitMsg(USER_TASK_NAME, MSG_KEY_PRESS)
            log.info("收到按键消息1",msg)
            if msg[2] then  -- true powerkey false boot key
                for i=1,#g_dev_list do
                    res = g_dev_list[i]["id"]
                    if res and res ~= mobile.imei() then     -- 不能本机和本机通话
                        break
                    end
                end
                extalk.start(res)     -- 开始一对一对讲
            else
                extalk.start()        -- 开始对群组广播
            end 
            msg = sys.waitMsg(USER_TASK_NAME, MSG_KEY_PRESS)   -- 再按一次就关闭对讲
            extalk.stop()       -- 停止对讲
        end
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