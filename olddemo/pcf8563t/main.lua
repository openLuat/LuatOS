
PROJECT = "pcf8563t"
VERSION = "2.0.0"

_G.sys = require "sys"

_G.pcf8563t = require "pcf8563t"

local function PCF8563T()

    sys.wait(3000)
    
    local i2cid = 1
    i2c.setup(i2cid, i2c.FAST)
    pcf8563t.setup(i2cid) -- 选一个i2c, 也可以是软件i2c对象
    
    -- 设置时间
    local time = {year=2023,mon=11,day=2,wday=5,hour=13,min=14,sec=15}
    pcf8563t.write(time)
    
    -- 读取时间
    local time = pcf8563t.read()
    log.info("time",time.year,time.mon,time.day, time.hour,time.min,time.sec, "week", time.wday)
    
    -- 设置闹钟, 并自动清除中断标志,开启alarm功能
    alarm = {day=2,hour=13,min=14,sec=15}
    pcf8563t.alarm(alarm)
    local alarm_int = 1 -- 选一个GPIO,接时钟模块的INT脚
    gpio.setup(1, function()
        log.info("alarm!!!")
        pcf8563t.control(nil, nil, 0, nil)
    end, gpio.PULLUP)
end
sys.taskInit(PCF8563T)

sys.run()
