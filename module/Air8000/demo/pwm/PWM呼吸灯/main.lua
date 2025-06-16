-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "pwmdemo"
VERSION = "1.0.1"

--[[
注意：Air8000_V2007及以上固件复用方式已经改为使用LuatIO工具。
本demo也已经使用LuatIO方式进行复用，代码中仅初始化PWM所用IO，没有进行复用操作。
运行本demo需要将pins_Air8000.json文件一并烧录进Air8000中，才能正常使用PWM功能。
LuatIO工具使用方法+下载地址：https://docs.openluat.com/air8000/common/luatio/?h=luatio
]]

log.info("main", PROJECT, VERSION)

-- sys库是标配
_G.sys = require("sys")

--添加硬狗防止程序卡死
if wdt then
    wdt.init(9000) -- 初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000)--3s喂一次狗
end

local PWM_ID = 4  -- 代码中使用pwm通道4，如需使用其他pwm通道请查看Air8000/pwm使用指南/pwm通道说明。
sys.taskInit(function()
    
    -- 设置演示所用的IO GPIO21 且初始化电平为低
    gpio.setup(21, 0)

    log.info("pwm", "ch", PWM_ID)
    while 1 do
        -- 仿呼吸灯效果
        log.info("pwm", ">>>>>")
        -- 占空比从90%（i=10时）到9%（i=1时）
        for i = 10,1,-1 do 
            pwm.open(PWM_ID, 1000, i*9) -- 频率1000hz, 占空比0-100
            sys.wait(100 + i*10)
        end
        -- 占空比从10%增加到90%
        for i = 10,1,-1 do 
            pwm.open(PWM_ID, 1000, 100 - i*9)
            sys.wait(100 + i*10)
        end
        sys.wait(2000)
    end
end) 

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!