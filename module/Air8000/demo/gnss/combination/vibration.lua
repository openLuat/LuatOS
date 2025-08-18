--[[
@module  vibration
@summary 利用加速度传感器da221实现中断触发gnss定位
@version 1.0
@date    2025.08.01
@author  李源龙
@usage
使用Air8000利用内置的da221加速度传感器实现震动中断触发gnss定位，给了两种方式，
第一种是加速度传感器震动之后触发，触发之后开始打开gnss，进行定位，定位成功之后每5s上传一次经纬度数据，
假设10s内没有再触发震动，则关闭gnss，等待下一次震动触发

第二种方式是震动触发之后计算为一次触发，如果10s内触发5次有效震动，则开启后续逻辑，如果10s内没有触发5次，
则判定为无效震动，等待下一次触发，如果是有效震动就打开gnss，进行定位，
定位成功之后每5s上传一次经纬度数据到服务器，有效震动触发之后有30分钟的等待时间，在此期间，如果触发有效震动则
不去进行后续逻辑处理，30分钟时间到了之后，等待下一次有效震动
具体使用哪种方式可以根据实际需求选择
]]

exvib=require("exvib")
tcp_client_main=require("tcp_client_main")

local intPin=gpio.WAKEUP2   --中断检测脚，内部固定wakeup2
local tid   --获取定时打开的定时器id
local num=0 --计数器 
local ticktable={0,0,0,0,0} --存放5次中断的tick值，用于做有效震动对比
local eff=false --有效震动标志位，用于判断是否触发定位


local function vib_cb(tag)
    log.info("TAGmode1_cb+++++++++",tag)
     local  rmc=exgnss.rmc(0)    --获取rmc数据
    log.info("nmea", "rmc", json.encode(exgnss.rmc(0)))
    local data=string.format('{"lat":%5f,"lng":%5f}', rmc.lat, rmc.lng)
    sys.publish("SEND_DATA_REQ", "gnssnormal", data) --发送数据到服务器

end
--定位成功就5s发送一包数据到服务器
local function gnss_state(event, ticks)
    -- event取值有
    -- "FIXED"：string类型 定位成功
    -- "LOSE"： string类型 定位丢失
    -- "CLOSE": string类型 GNSS关闭，仅配合使用gnss.lua有效

    -- ticks number类型 是事件发生的时间,一般可以忽略
    log.info("exgnss", "state", event)
    if event=="FIXED" then
        log.info("定位成功")
    end
end

sys.subscribe("GNSS_STATE",gnss_state)

--有效震动模式
--tick计数器，每秒+1用于存放5次中断的tick值，用于做有效震动对比
-- local function tick()
--     num=num+1
-- end
-- --每秒运行一次计时
-- sys.timerLoopStart(tick,1000)

-- --有效震动判断
-- local function ind()
--     log.info("int", gpio.get(intPin))
--     if gpio.get(intPin) == 1 then
--         --接收数据如果大于5就删掉第一个
--         if #ticktable>=5 then
--             log.info("table.remove",table.remove(ticktable,1))
--         end
--         --存入新的tick值
--         table.insert(ticktable,num)
--         log.info("tick",num,(ticktable[5]-ticktable[1]<10),ticktable[5]>0)
--         log.info("tick2",ticktable[1],ticktable[2],ticktable[3],ticktable[4],ticktable[5])
--         --表长度为5且，第5次中断时间间隔减去第一次间隔小于10s，且第5次值为有效值
--         if #ticktable>=5 and (ticktable[5]-ticktable[1]<10 and ticktable[1]>0) then
--             log.info("vib", "xxx")
--             --是否要去触发有效震动逻辑
--             if eff==false then
--                 sys.publish("EFFECTIVE_VIBRATION")
--             end
--         end
--     end
-- end

-- --设置30s分钟之后再判断是否有效震动函数
-- local function num_cb()
--     eff=false
-- end

-- local function eff_vib()
--     --触发之后eff设置为true，30分钟之后再触发有效震动
--     eff=true
--     --30分钟之后再触发有效震动
--     sys.timerStart(num_cb,180000)
--     --判断gnss是否处于打开状态
--     if exgnss.is_active(exgnss.DEFAULT,{tag="vib"})~=true then
--         log.info("nmea", "is_open", "false")
--         exgnss.open(exgnss.DEFAULT,{tag="vib",cb=vib_cb}) 
--         tid=sys.timerLoopStart(vib_cb, 5000)
--     else
--         log.info("nmea", "is_open", "true")
--     end
-- end

-- sys.subscribe("EFFECTIVE_VIBRATION",eff_vib)



--持续震动模式
--10s没有触发中断就停止
local function vib_close()
    exgnss.close(exgnss.DEFAULT,{tag="vib"})
    sys.timerStop(tid)
end

--持续震动模式中断函数
local function ind()
    log.info("int", gpio.get(intPin))
    if gpio.get(intPin) == 1 then
        --10s没有触发中断就停止
        sys.timerStart(vib_close,10000)
        local x,y,z =  exvib.read_xyz()      --读取x，y，z轴的数据
        log.info("x", x..'g', "y", y..'g', "z", z..'g')
        --判断gnss是否处于打开状态
        if exgnss.is_active(exgnss.DEFAULT,{tag="vib"})~=true then
            log.info("nmea", "is_open", "false")
            exgnss.open(exgnss.DEFAULT,{tag="vib",cb=vib_cb}) 
            tid=sys.timerLoopStart(vib_cb, 5000)
        else
            log.info("nmea", "is_open", "true")
        end
    end
end


local function gnss_fnc()
    log.info("gnss_fnc111")
    local gnssotps={
        gnssmode=1, --1为卫星全定位，2为单北斗
        agps_enable=true,    --是否使用AGPS，开启AGPS后定位速度更快，会访问服务器下载星历，星历时效性为北斗1小时，GPS4小时，默认下载星历的时间为1小时，即一小时内只会下载一次
        debug=true,    --是否输出调试信息
        -- uart=2,    --使用的串口,780EGH和8000默认串口2
        -- uartbaud=115200,    --串口波特率，780EGH和8000默认115200
        -- bind=1, --绑定uart端口进行GNSS数据读取，是否设置串口转发，指定串口号
        -- rtc=false    --定位成功后自动设置RTC true开启，flase关闭
        ----因为GNSS使用辅助定位的逻辑，是模块下载星历文件，然后把数据发送给GNSS芯片，
        ----芯片解析星历文件需要10-30s，默认GNSS会开启20s，该逻辑如果不执行，会导致下一次GNSS开启定位是冷启动，
        ----定位速度慢，大概35S左右，所以默认开启，如果可以接受下一次定位是冷启动，可以把auto_open设置成false
        ----需要注意的是热启动在定位成功之后，需要再开启3s左右才能保证本次的星历获取完成，如果对定位速度有要求，建议这么处理
        -- auto_open=false 
    }
    exgnss.setup(gnssotps)
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

sys.taskInit(gnss_fnc)

