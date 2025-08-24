--[[
@module  vibration
@summary 利用加速度传感器da221实现震动触发中断，然后处理逻辑
@version 1.0
@date    2025.08.01
@author  李源龙
@usage
使用Air8000整机开发板，本示例主要是展示exvib库的使用，提供了三种场景应用：

1，微小震动检测：用于检测轻微震动的场景，例如用手敲击桌面；加速度量程2g；

2，运动检测：用于电动车或汽车行驶时的检测和人行走和跑步时的检测；加速度量程4g；

3，跌倒检测：用于人或物体瞬间跌倒时的检测；加速度量程8g；

在震动检测方面提供了两种模式，有效震动模式和持续震动检测模式：

持续震动检测模式：震动强度超过设定阈值时，会进入中断处理函数，获取xyz三轴的数据

有效震动模式：当10秒内触发5次震动强度超过设定阈值时，持续触发震动事件，并执行相应的处理函数，30分钟内只能触发一次，直到30分钟之后，再重新开始检测
]]

exvib=require("exvib")

local intPin=gpio.WAKEUP2   --中断检测脚，内部固定wakeup2
local tid   --获取定时打开的定时器id
local num=0 --计数器 
local ticktable={0,0,0,0,0} --存放5次中断的tick值，用于做有效震动对比
local eff=false --有效震动标志位，用于判断是否触发定位

gpio.setup(164, 1, gpio.PULLUP) -- air8000整机板需要大概该电源控制i2c上电 和音频解码芯片共用，自己设计可以忽略掉
gpio.setup(147, 1, gpio.PULLUP) -- air8000整机板需要大概该电源控制i2c上电 camera的供电使能脚，自己设计可以忽略掉
--有效震动模式
--tick计数器，每秒+1用于存放5次中断的tick值，用于做有效震动对比
local function tick()
    num=num+1
end
--每秒运行一次计时
sys.timerLoopStart(tick,1000)

--有效震动判断
local function ind()
    log.info("int", gpio.get(intPin))
    if gpio.get(intPin) == 1 then
        --接收数据如果大于5就删掉第一个
        if #ticktable>=5 then
            log.info("table.remove",table.remove(ticktable,1))
        end
        --存入新的tick值
        table.insert(ticktable,num)
        log.info("tick",num,(ticktable[5]-ticktable[1]<10),ticktable[5]>0)
        log.info("tick2",ticktable[1],ticktable[2],ticktable[3],ticktable[4],ticktable[5])
        --表长度为5且，第5次中断时间间隔减去第一次间隔小于10s，且第5次值为有效值
        if #ticktable>=5 and (ticktable[5]-ticktable[1]<10 and ticktable[1]>0) then
            log.info("vib", "xxx")
            --是否要去触发有效震动逻辑
            if eff==false then
                sys.publish("EFFECTIVE_VIBRATION")
            end
        end
    end
end

--设置30s分钟之后再判断是否有效震动函数
local function num_cb()
    eff=false
end

local function eff_vib()
    log.info("触发有效震动")
    --触发之后eff设置为true，30分钟之后再触发有效震动
    eff=true
    --30分钟之后再触发有效震动
    sys.timerStart(num_cb,180000)
end

sys.subscribe("EFFECTIVE_VIBRATION",eff_vib)



--持续震动模式

--持续震动模式中断函数
-- local function ind()
--     log.info("int", gpio.get(intPin))
--     --上升沿为触发震动中断
--     if gpio.get(intPin) == 1 then
--         local x,y,z =  exvib.read_xyz()      --读取x，y，z轴的数据
--         log.info("x", x..'g', "y", y..'g', "z", z..'g')
--     end
-- end


local function vib_fnc()
    -- 1，微小震动检测，用于检测轻微震动的场景，例如用手敲击桌面；加速度量程2g；
    -- 2，运动检测，用于电动车或汽车行驶时的检测和人行走和跑步时的检测；加速度量程4g；
    -- 3，跌倒检测，用于人或物体瞬间跌倒时的检测；加速度量程8g；
    --打开震动检测功能
    exvib.open(1)
    --设置gpio防抖100ms
    gpio.debounce(intPin, 100)
    --设置gpio中断触发方式wakeup2唤醒脚默认为双边沿触发
    gpio.setup(intPin, ind)

end

sys.taskInit(vib_fnc)

