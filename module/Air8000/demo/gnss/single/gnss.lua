--[[
@module  gnss
@summary gnss应用测试功能模块
@version 1.0
@date    2025.07.27
@author  李源龙
@usage
该文件演示的功能会用到exgnss.lua扩展库

--关于exgnss的三种应用场景：
exgnss.DEFAULT:
--- exgnss应用模式1.
-- 打开gnss后，gnss定位成功时，如果有回调函数，会调用回调函数
-- 使用此应用模式调用exgnss.open打开的“gnss应用”，必须主动调用exgnss.close
-- 或者exgnss.close_all才能关闭此“gnss应用”,主动关闭时，即使有回调函数，也不会调用回调函数
-- 通俗点说就是一直打开，除非自己手动关闭掉

exgnss.TIMERORSUC:
--- exgnss应用模式2.
-- 打开gnss后，如果在gnss开启最大时长到达时，没有定位成功，如果有回调函数，
-- 会调用回调函数，然后自动关闭此“gnss应用”
-- 打开gnss后，如果在gnss开启最大时长内，定位成功，如果有回调函数，
-- 会调用回调函数，然后自动关闭此“gnss应用”
-- 打开gnss后，在自动关闭此“gnss应用”前，可以调用exgnss.close或者
-- exgnss.close_all主动关闭此“gnss应用”，主动关闭时，即使有回调函数，也不会调用回调函数
-- 通俗点说就是设置规定时间打开，如果规定时间内定位成功就会自动关闭此应用，
-- 如果没有定位成功，时间到了也会自动关闭此应用

exgnss.TIMER:
--- exgnss应用模式3.
-- 打开gnss后，在gnss开启最大时长时间到达时，无论是否定位成功，如果有回调函数，
-- 会调用回调函数，然后自动关闭此“gnss应用”
-- 打开gnss后，在自动关闭此“gnss应用”前，可以调用exgnss.close或者exgnss.close_all
-- 主动关闭此“gnss应用”，主动关闭时，即使有回调函数，也不会调用回调函数
-- 通俗点说就是设置规定时间打开，无论是否定位成功，到了时间都会自动关闭此应用，
-- 和第二种的区别在于定位成功之后不会自动关闭，到时间之后才会自动关闭

本示例主要是展示exgnss库的三种应用模式，然后关闭操作和查询应用是否有效操作，还有关闭全部应用操作，
以及定位成功之后如何使用exgnss库获取gnss的rmc数据
]]

local function mode1_cb(tag)
    log.info("TAGmode1_cb+++++++++",tag)
    log.info("nmea", "rmc", json.encode(exgnss.rmc(2)))
end

local function mode2_cb(tag)
    log.info("TAGmode2_cb+++++++++",tag)
    log.info("nmea", "rmc", json.encode(exgnss.rmc(2)))
end

local function mode3_cb(tag)
    log.info("TAGmode3_cb+++++++++",tag)
    log.info("nmea", "rmc", json.encode(exgnss.rmc(2)))
end

local function gnss_fnc()
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
    --设置gnss参数
    exgnss.setup(gnssotps)
    --开启gnss应用
    exgnss.open(exgnss.TIMER,{tag="modeTimer",val=60,cb=mode1_cb})  --使用TIMER模式，开启60s后关闭
    exgnss.open(exgnss.DEFAULT,{tag="modeDefault",cb=mode2_cb}) --使用DEFAULT模式，开启后一直运行  
    exgnss.open(exgnss.TIMERORSUC,{tag="modeTimerorsuc",val=60,cb=mode3_cb})    --使用TIMERORSUC模式，开启60s，如果定位成功，则直接关闭
    sys.wait(40000)
    log.info("关闭一个gnss应用，然后查看下所有应用的状态")
    --关闭一个gnss应用
    exgnss.close(exgnss.TIMER,{tag="modeTimer"})--关闭tag为modeTimer应用
    --查询3个gnss应用状态
    log.info("gnss应用状态1",exgnss.is_active(exgnss.TIMER,{tag="modeTimer"}))
    log.info("gnss应用状态2",exgnss.is_active(exgnss.DEFAULT,{tag="modeDefault"}))
    log.info("gnss应用状态3",exgnss.is_active(exgnss.TIMERORSUC,{tag="modeTimerorsuc"}))
    sys.wait(10000)
    --关闭所有gnss应用
    exgnss.close_all()
    --查询3个gnss应用状态
    log.info("gnss应用状态1",exgnss.is_active(exgnss.TIMER,{tag="modeTimer"}))
    log.info("gnss应用状态2",exgnss.is_active(exgnss.DEFAULT,{tag="modeDefault"}))
    log.info("gnss应用状态3",exgnss.is_active(exgnss.TIMERORSUC,{tag="modeTimerorsuc"}))
    --查询最后一次定位结果
    local loc= exgnss.last_loc()
    if loc then
        log.info("lastloc", loc.lat,loc.lng)
    end
end

sys.taskInit(gnss_fnc)


--GNSS定位状态的消息处理函数：
local function gnss_state(event, ticks)
    -- event取值有
    -- "FIXED"：string类型 定位成功
    -- "LOSE"： string类型 定位丢失
    -- "CLOSE": string类型 GNSS关闭，仅配合使用gnss.lua有效

    -- ticks number类型 是事件发生的时间,一般可以忽略
    log.info("exgnss", "state", event)
    if event=="FIXED" then
        --获取rmc数据
        --json.encode默认输出"7f"格式保留7位小数，可以根据自己需要的格式调整小数位，本示例保留5位小数
        log.info("nmea", "rmc0", json.encode(exgnss.rmc(0),"5f"))
    end
end
sys.subscribe("GNSS_STATE",gnss_state)