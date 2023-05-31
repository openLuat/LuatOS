
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "pmdemo"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- sys库是标配
_G.sys = require("sys")

-- 注意:本demo使用luatools下载!!!
-- 注意:本demo使用luatools下载!!!
-- 注意:本demo使用luatools下载!!!


-- 启动时对rtc进行判断和初始化
local t = rtc.get()
log.info("rtc", json.encode(t))
if t["year"] == 1900 then
    -- 对air101/air103来说
    -- 若复位启动, 那rtc时间必然是1900年, 设置时间就行
    -- 若为唤醒, 那rtc时间必然已经设置过, 肯定不是1900, 就不用设置了
    rtc.set({year=2022,mon=9,day=1,hour=0,min=0,sec=0})
end
t = nil -- 释放t这个变量

--添加硬狗防止程序卡死
wdt.init(9000)--初始化watchdog设置为9s
sys.timerLoopStart(wdt.feed, 3000)--3s喂一次狗

local LEDA = gpio.setup(24, 0, gpio.PULLUP) -- PB8输出模式
local LEDB = gpio.setup(25, 0, gpio.PULLUP) -- PB9输出模式
local LEDC = gpio.setup(26, 0, gpio.PULLUP) -- PB10输出模式


-- 这里启动的task也是闪灯, 用于展示休眠状态
sys.taskInit(function()
    local count = 0
    local uid = mcu.unique_id() or ""
    while 1 do
        -- 一闪一闪亮晶晶
        LEDA(count & 0x01 == 0x01 and 1 or 0)
        LEDB(count & 0x02 == 0x02 and 1 or 0)
        LEDC(count & 0x03 == 0x03 and 1 or 0)
        log.info("gpio", "Go Go Go", uid:toHex(), count)
        sys.wait(1000)
        count = count + 1
    end
end)

sys.taskInit(function()
    -- 对于air101/air103来说, request之后马上就会休眠
    -- 如果没有休眠, 请检查wakeup脚的电平
    -- 休眠分2种情况, RAM不掉电的LIGHT 和 RAM掉电的HIB

    -- 这里的sys.wait是为了开机后不会马上休眠
    -- 实际情况是跑业务代码, 条件符合后休眠,这里是sys.wait只是演示业务执行
    sys.wait(3000)

    -- 先演示LIGHT模式休眠, RAM不掉电, IO保持, 唤醒后代码继续跑
    -- 设置休眠时长
    log.info("pm", "轻休眠15秒", "要么rtc唤醒,要么wakeup唤醒", "RAM不掉电")
    log.info("rtc", json.encode(rtc.get()))
    pm.dtimerStart(0, 15000)
    pm.request(pm.LIGHT)
    -- 后面的语句, 正常情况下会在15000ms后执行
    log.info("pm", "轻睡眠唤醒", "代码继续跑")
    -- 这里等待3000ms,模拟业务执行,期间gpio的闪灯task将继续运行
    log.info("rtc", json.encode(rtc.get()))
    sys.wait(3000)

    -- 测试一下RTC唤醒
    local t = rtc.get()
    if t.sec < 30 then
        log.info("rtc", "轻唤醒测试", "5秒后唤醒")
        t.sec = t.sec + 5
        rtc.timerStart(0, t)
        pm.request(pm.LIGHT)
        log.info("rtc", "轻唤醒测试", "唤醒成功")

        -- RTC深度休眠+唤醒
        -- t.sec = t.sec + 5
        -- rtc.timerStart(0, t)
        -- log.info("rtc", "深唤醒测试", "5秒后唤醒")
        -- pm.request(pm.DEEP)
    end

    -- 接着演示 DEEP模式休眠, RAM掉电, IO失效, 唤醒相当于复位重启
    -- 因为已经唤醒过,dtimer已经失效, 重新设置一个
    log.info("rtc", json.encode(rtc.get()))
    log.info("pm", "深休眠5秒", "要么rtc唤醒,要么wakeup唤醒", "RAM掉电")
    pm.dtimerStart(0, 5000)
    pm.request(pm.DEEP)
    -- 后面代码都不会执行, 如果执行了, 那100%是wakeup电平有问题
    log.info("pm", "这里的代码不会被执行")
    log.info("rtc", json.encode(rtc.get()))
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
