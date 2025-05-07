
--[[
1. 本demo可直接在Air8000整机开发板上运行，如有需要请luat.taobao.com 购买
2. 本demo 不可以和camera，led一起使用
3. 摄像头使用了如下管脚
       [14, "POWER_ON", " PIN14脚, 开机控制"],
4. 本程序使用逻辑：
4.1. 如果按下开机键，5秒之内不松手，则将air8000 关机，如果5秒之内松手则不关机
4.1. 点击boot 后，将打印 “boot 键 按下”
]]

local taskName ="task_key"
local powerkey_pin = gpio.PWR_KEY   -- 开机键
local boot_pin =      0             -- Boot 按键ID
local MSG_POWERKEY_PRESS =  "POWERKEY_PRESS"
local MSG_POWERKEY_RISE =  "POWERKEY_RISE"
local MSG_BOOT_RISE =  "BOOT_RISE"
local msg = nil



function pwroff()
    log.info("power off!!")
    pm.shutdown()
end

local function pwrkeycb()    --长按五秒关机
    if gpio.get(powerkey_pin) == 1 then
        sysplus.sendMsg(taskName, MSG_POWERKEY_RISE)
    else
        sysplus.sendMsg(taskName, MSG_POWERKEY_PRESS)
    end
end

local function bootcb()
    sysplus.sendMsg(taskName,MSG_BOOT_RISE)
end

local function setup_gpio()
    gpio.setup(powerkey_pin, pwrkeycb, gpio.PULLUP,gpio.BOTH)       -- 配置
    gpio.setup(boot_pin, bootcb, gpio.PULLDOWN, gpio.RISING)     -- 配置boot 按键，设置
    gpio.debounce(boot_pin , 100, 1)                                -- 设置按键防抖动100ms
end



local function key_task()
    setup_gpio()    --  初始化485
    while true do
        msg = sysplus.waitMsg(taskName, nil)                    -- 等待key task 的消息
        if type(msg) == 'table' then
            if msg[1] == MSG_POWERKEY_PRESS then
                log.info("pwrkey 按下，计时5秒后关机")
                sys.timerStart(pwroff, 5000)                    -- 开关机按下后，如果5秒内没有松开，就进入关机程序
            elseif  msg[1] == MSG_POWERKEY_RISE then
                log.info("pwrkey 抬起，取消关机")
                sys.timerStop(pwroff)                           -- 取消关机动作
            elseif  msg[1] == MSG_BOOT_RISE then
                log.info("boot 键 按下 ")                        -- boot 按键按下
            end
        else
            log.error(type(msg), msg)
        end
    end
end


sysplus.taskInitEx(key_task, taskName)  
