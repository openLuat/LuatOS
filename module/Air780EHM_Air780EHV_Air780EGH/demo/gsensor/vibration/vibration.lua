--[[
@module  vibration
@summary 利用加速度传感器da221实现中断触发gnss定位
@version 1.0
@date    2025.08.01
@author  李源龙
@usage
注意：该demo只有780EGG/Air780EGP支持，780EGH不支持，因为没有内置da221加速度传感器
使用Air780EGG/Air780EGP利用内置的da221加速度传感器实现震动中断触发gnss定位，给了两种方式，
第一种是加速度传感器震动之后触发，触发之后开始打开gnss，进行定位，定位成功之后每5s上传一次经纬度数据，
假设10s内没有再触发震动，则关闭gnss，等待下一次震动触发

第二种方式是震动触发之后计算为一次触发，如果10s内触发5次有效震动，则开启后续逻辑，如果10s内没有触发5次，
则判定为无效震动，等待下一次触发，如果是有效震动就打开gnss，进行定位，
定位成功之后每5s上传一次经纬度数据到服务器，有效震动触发之后有30分钟的等待时间，在此期间，如果触发有效震动则
不去进行后续逻辑处理，30分钟时间到了之后，等待下一次有效震动
具体使用哪种方式可以根据实际需求选择
]]

exvib=require("exvib")

local intPin=gpio.WAKEUP2   --中断检测脚，内部固定wakeup2
local tid   --获取定时打开的定时器id
local num=0 --计数器 
local ticktable={0,0,0,0,0} --存放5次中断的tick值，用于做有效震动对比
local eff=false --有效震动标志位，用于判断是否触发定位
local ipready=false --网络是否连接成功标志位
local tickid

--有效震动模式
--tick计数器，每秒+1用于存放5次中断的tick值，用于做有效震动对比
local function tick()
    num=num+1
end
-- --每秒运行一次计时
tickid=sys.timerLoopStart(tick,1000)

--有效震动判断
local function ind()
    log.info("int", gpio.get(intPin))
    if gpio.get(intPin) == 1 then
        --接收数据如果大于5就删掉第一个
        if #ticktable>=5 then
            log.info("table.remove",table.remove(ticktable,1))
        end
        --存入新的tick值
        if not ipready then
            log.info("ipready",ipready)
            table.insert(ticktable,num)
        else
            log.info("ipready2",ipready)
            table.insert(ticktable,os.time())
        end
        log.info("tick",os.time(),(ticktable[5]-ticktable[1]<10),ticktable[5]>0)
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

-- --持续震动模式中断函数
-- local function ind()
--     log.info("int", gpio.get(intPin))
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
    while not socket.adapter(socket.dft()) do
        log.warn("mqtt_client_main_task_func", "wait IP_READY", socket.dft())
        -- 在此处阻塞等待默认网卡连接成功的消息"IP_READY"
        -- 或者等待1秒超时退出阻塞等待状态;
        -- 注意：此处的1000毫秒超时不要修改的更长；
        -- 因为当使用exnetif.set_priority_order配置多个网卡连接外网的优先级时，会隐式的修改默认使用的网卡
        -- 当exnetif.set_priority_order的调用时序和此处的socket.adapter(socket.dft())判断时序有可能不匹配
        -- 此处的1秒，能够保证，即使时序不匹配，也能1秒钟退出阻塞状态，再去判断socket.adapter(socket.dft())
        sys.waitUntil("IP_READY", 1000)
    end
    sys.timerStop(tickid)
    sys.wait(1000)
    ipready=true
    if ticktable[1]~=0 then
        log.info("os.time()-((num+1)-ticktable[1])",os.time()-((num+1)-ticktable[1]))
        ticktable[1]=os.time()-((num+1)-ticktable[1])
    end
    if ticktable[2]~=0 then
        log.info("os.time()-((num+1)-ticktable[2])",os.time()-((num+1)-ticktable[2]))
        ticktable[2]=os.time()-((num+1)-ticktable[2])
    end
    if ticktable[3]~=0 then
        log.info("os.time()-((num+1)-ticktable[3])",os.time()-((num+1)-ticktable[3]))
        ticktable[3]=os.time()-((num+1)-ticktable[3])
    end
    if ticktable[4]~=0 then
        log.info("os.time()-((num+1)-ticktable[4])",os.time()-((num+1)-ticktable[4]))
        ticktable[4]=os.time()-((num+1)-ticktable[4])
    end
    if ticktable[5]~=0 then
        log.info("os.time()-((num+1)-ticktable[5])",os.time()-((num+1)-ticktable[5]))
        ticktable[5]=os.time()-((num+1)-ticktable[5])
    end
end

sys.taskInit(vib_fnc)

