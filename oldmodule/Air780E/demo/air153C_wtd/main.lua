PROJECT = 'air153C_wtd'
VERSION = '2.0.0'
LOG_LEVEL = log.LOG_INFO
log.setLevel(LOG_LEVEL )
require 'air153C_wtd'
local sys = require "sys"
_G.sysplus = require("sysplus")

--[[
    对于喂狗以及关闭喂狗，调用函数时需要等待对应的时间
    例如:   1. 喂狗是410ms，那么需要等待至少400ms，即
            air153C_wtd.feed_dog(pin)
            sys.wait(410ms)
            2. 关闭喂狗是710ms，那么需要等待至少700ms
            air153C_wtd.close_watch_dog(pin)
            sys.wait(710ms)
]]

sys.taskInit(function ()
    log.info("main","taskInit")
    local flag = 0
    air153C_wtd.init(28)
    air153C_wtd.feed_dog(28)--模块开机第一步需要喂狗一次
    sys.wait(3000)--此处延时3s，防止1s内喂狗2次导致进入测试模式


    --不喂狗
    log.info("WTD","not eatdog test start!")
    while 1 do
        flag=flag+1
        log.info("not feed dog",flag)
        sys.wait(1000)
    end


    --喂狗
    -- log.info("WTD","eatdog test start!")
    -- while 1 do
    -- air153C_wtd.feed_dog(28)--28为看门狗控制引脚
    -- log.info("main","feed dog")
    -- sys.wait(200000)
    -- end

    
    --关闭喂狗
    -- log.info("WTD","close eatdog test start!")
    -- air153C_wtd.close_watch_dog(28)--28为看门狗控制引脚
    -- sys.wait(1000)
    

    --先关闭喂狗，再打开喂狗
    -- log.info("WTD","close eatdog and open eatdog test start!")
    -- while 1 do
    --     if flag==0 then
    --         flag = 1
    --         log.info("main","close watch dog")
    --         air153C_wtd.close_watch_dog(28)--28为看门狗控制引脚
    --         sys.wait(30000) --方便观察设置的时间长一点
    --     end
    --     flag=flag+1
    --     if flag == 280 then
    --         log.info("main","feed dog")
    --         air153C_wtd.feed_dog(28)
    --     end
    --     sys.wait(1000)
    --     log.info("Timer count(1s):", flag);
    -- end


    --测试模式复位
    --测试模式： 1s内喂狗2次，会使模块复位重启
    -- log.info("WTD","testmode test start!")
    -- while flag<2 do
    -- flag =flag+ 1
    -- air153C_wtd.feed_dog(28)--28为看门狗控制引脚
    -- log.info("main","feed dog")
    -- sys.wait(500)
    -- end
end)

sys.run()
