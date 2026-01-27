local gnss={}

local exvib=require "exvib"
local exgnss=require "exgnss"
local default=require "default"

local dtu


local openFlag=false



local intPin=gpio.WAKEUP2   --中断检测脚，内部固定wakeup2
local tid   --获取定时打开的定时器id
local num=0 --计数器 
local ticktable={0,0,0,0,0} --存放5次中断的tick值，用于做有效震动对比
local eff=false --有效震动标志位，用于判断是否触发定位
local s_isclose=false --是否关闭GPS
local s_ontime=60
local s_gtime=1800
local gpscid=1
local s_tid
local ipready=false --网络是否连接成功标志位
--有效震动模式
--tick计数器，每秒+1用于存放5次中断的tick值，用于做有效震动对比
local function tick()
    num=num+1
end

local tickid=sys.timerLoopStart(tick,1000)

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
    log.info("触发有效震动",s_gtime,s_isclose,s_ontime)
    if s_ontime==0 then
        exgnss.open(exgnss.DEFAULT,{tag="gnss"})
    elseif s_isclose==0 and s_ontime>0 then
        exgnss.open(exgnss.TIMER,{tag="gnss",val=s_ontime})
    elseif s_isclose==1 and s_ontime>0 then
        exgnss.open(exgnss.TIMERORSUC,{tag="gnss",val=s_ontime})
    end
    eff=true
    --30分钟之后再触发有效震动
    sys.timerStop(s_tid)
    sys.timerStart(num_cb,s_gtime*1000)
end

sys.subscribe("EFFECTIVE_VIBRATION",eff_vib)

-- 上传定位信息
-- [是否有效,时间戳,经度,纬度,海拔,方位角,速度,定位卫星]
-- 用户自定义上报GPS数据的报文顺序
-- msg = {"isfix", "stamp", "lng", "lat", "altitude", "azimuth", "speed", "sateCnt"},
function gnss.locateMessage(mode)
    local sendtable={rmc={}, gga={}, vtg={}}
    if mode.rmc then
        sendtable.rmc = exgnss.rmc(0)
    end
    if mode.gga then
        sendtable.gga = exgnss.gga(0)
    end
    if mode.vtg then
        sendtable.vtg = exgnss.vtg()
    end
    if mode.custom then
        if mode.custom_data:match("function(.+)end") then
            return loadstring(mode.custom_data:match("function(.+)end"))()
        end
    end
    log.info("sendjason",json.encode(sendtable,"5f"))
    return json.encode(sendtable,"5f")
end

--GNSS定位状态的消息处理函数：
local function gnss_state(event, ticks)
    -- event取值有
    -- "FIXED"：string类型 定位成功
    -- "LOSE"： string类型 定位丢失
    -- "CLOSE": string类型 GNSS关闭，仅配合使用exgnss.lua有效

    -- ticks number类型 是事件发生的时间,一般可以忽略
    log.info("exgnss", "state", event)
    if event=="FIXED" then
       sys.publish("NET_SENT_RDY_1","GPSCID_"..gpscid,locateMessage(dtu.gps.fun[8]))
       sys.publish("NET_SENT_RDY_3","GPSCID_"..gpscid,locateMessage(dtu.gps.fun[8]))
       if dtu.gps.fun[5] ==1 then
        log.info("定位成功就关掉了")
       else
        tid=sys.timerLoopStart(function()
            sys.publish("NET_SENT_RDY_1","GPSCID_"..gpscid,locateMessage(dtu.gps.fun[8]))
            sys.publish("NET_SENT_RDY_3","GPSCID_"..gpscid,locateMessage(dtu.gps.fun[8]))
        end,dtu.gps.fun[3]*1000)
       end
    end
    if event=="CLOSE" then
        sys.timerStop(tid)
    end
end
sys.subscribe("GNSS_STATE",gnss_state)

-- 串口ID,波特率，上报间隔，打开gps的时间,定位成功之后是否关闭gps, 采集方式，,上报通道,上报内容，震动触发采集间隔时间
function alert(uid, baud, interval, ontime, isclose, gather, cid, pubmsg, gtime,timing)
    log.info("pubmsg",pubmsg,type(pubmsg))
    log.info("ISCLOSE",isclose)
    s_isclose=isclose
    s_ontime=ontime
    s_gtime=gtime
    gpscid=cid
    local cnt=0
    local gnssotps={
            gnssmode=1, --1为卫星全定位，2为单北斗
            agps_enable=true,    --是否使用AGPS，开启AGPS后定位速度更快，会访问服务器下载星历，星历时效性为北斗1小时，GPS4小时，默认下载星历的时间为1小时，即一小时内只会下载一次
            debug=true,    --是否输出调试信息
            uart=uid,    --使用的串口,780EGH和8000默认串口2
            uartbaud=baud,    --串口波特率，780EGH和8000默认115200
            -- bind=1, --绑定uart端口进行GNSS数据读取，是否设置串口转发，指定串口号
            -- rtc=false    --定位成功后自动设置RTC true开启，flase关闭
            ----因为GNSS使用辅助定位的逻辑，是模块下载星历文件，然后把数据发送给GNSS芯片，
            ----芯片解析星历文件需要10-30s，默认GNSS会开启20s，该逻辑如果不执行，会导致下一次GNSS开启定位是冷启动，
            ----定位速度慢，大概35S左右，所以默认开启，如果可以接受下一次定位是冷启动，可以把auto_open设置成false
            ----需要注意的是热启动在定位成功之后，需要再开启3s左右才能保证本次的星历获取完成，如果对定位速度有要求，建议这么处理
            -- auto_open=false,
            -- 定位频率，指gnss每秒输出多少次的定位数据，1hz=1秒/次，默认1hz，可选值：1/2/4/5
            -- hz=1,
        }
    exgnss.setup(gnssotps)  --配置GNSS参数
    while true do
        if exgnss.is_active(exgnss.TIMER,{tag="gnss"}) then 
        
        elseif gather==0 then
            log.info("振动监测")
            --打开震动检测功能
            exvib.open(1)
            --设置gpio防抖100ms
            gpio.debounce(intPin, 100)
            --设置gpio中断触发方式wakeup2唤醒脚默认为双边沿触发
            gpio.setup(intPin, ind)
            while not socket.adapter(socket.dft()) do
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
        else
            log.info("0---------------------------0", "GPS 任务启动")
            if ontime==0 then
                exgnss.open(exgnss.DEFAULT,{tag="gnss"})
            elseif isclose==0 and ontime>0 then
                exgnss.open(exgnss.TIMER,{tag="gnss",val=ontime})
                g_tid=sys.timerLoopStart(function()
                    exgnss.open(exgnss.TIMER,{tag="gnss",val=ontime})
                end,timing*1000)
            elseif isclose==1 and ontime>0 then
                exgnss.open(exgnss.TIMERORSUC,{tag="gnss",val=ontime})
                g_tid=sys.timerLoopStart(function()
                    exgnss.open(exgnss.TIMERORSUC,{tag="gnss",val=ontime})
                end,timing*1000)
            end
        end
        sys.waitUntil("GPS_OPEN")
    end
end


-- 启动GPS任务
function gnss.init()
    dtu= default.get()
    if dtu.gps and dtu.gps.fun and tonumber(dtu.gps.fun[1]) then
        sys.taskInit(alert, unpack(dtu.gps.fun))
    end
end


return gnss