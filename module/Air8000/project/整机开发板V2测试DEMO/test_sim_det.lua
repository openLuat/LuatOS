
--[[
1. 本demo可直接在Air8000整机开发板上运行，如有需要请luat.taobao.com 购买
2. 使用了如下管脚0
       [43, "WAKEUP6", " PIN43脚, 用作检测SIM卡插拔"],
3. 本程序使用逻辑：
3.1. 插入SIM卡,会产生一个事件打印
]]

local taskName ="task_sim_det"
local sim_det_gpio = gpio.WAKEUP6   -- SIM卡插入检测IO
local MSG_SIM_PULL =  "SIM_PULL"
local MSG_SIM_INSERT =  "SIM_INSERT"
local msg = nil



function pwroff()
    log.info("power off!!")
    pm.shutdown()
end

local function sim_dey_cb()    
    if gpio.get(sim_det_gpio) == 0 then
        sysplus.sendMsg(taskName, MSG_SIM_PULL)
    else
        sysplus.sendMsg(taskName, MSG_SIM_INSERT)
    end
end


local function setup_gpio()
    gpio.setup(gpio.WAKEUP6, sim_dey_cb, gpio.PULLUP,gpio.BOTH)       -- 配置sim 卡中断脚

end



local function sim_det_task()
    setup_gpio()    --  初始化485
    while true do
        msg = sysplus.waitMsg(taskName, nil)                    -- 等待sim task 的消息
        if type(msg) == 'table' then
            if msg[1] == MSG_SIM_INSERT then                      
                log.info("sim 卡插入!!")
            elseif msg[1] == MSG_SIM_PULL   then
                log.info("sim 卡拔出!!")
            end
        else
            log.error(type(msg), msg)
        end
    end
end


sysplus.taskInitEx(sim_det_task, taskName)   
