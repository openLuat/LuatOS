--[[
@module  lowpower
@summary gnss低功耗测试功能模块
@version 1.0
@date    2025.07.27
@author  李源龙
@usage
使用Air780EGH核心板，外接GPS天线，起一个60s定位一次的定时器，唤醒模块60s一定位，然后定位成功获取到经纬度发送到服务器上面，然后进入休眠
]]

gnss=require("gnss")
tcp=require("tcp")

local function mode1_cb(tag)
    log.info("TAGmode1_cb+++++++++",tag)
    local  rmc=gnss.getRmc(0)
    log.info("nmea", "rmc", json.encode(gnss.getRmc(0)))
    tcp.latlngfnc(rmc.lat,rmc.lng)
    pm.power(pm.WORK_MODE, 1)
end
local function timer1()
    pm.power(pm.WORK_MODE, 0)
    gnss.open(gnss.TIMERORSUC,{tag="MODE1",val=60,cb=mode1_cb})
end

local function gnss_fnc()
    log.info("gnss_fnc111")
    local gnssotps={
        gnssmode=1, --1为卫星全定位，2为单北斗
        agps_enable=true,    --是否使用AGPS，开启AGPS后定位速度更快，会访问服务器下载星历，星历时效性为北斗1小时，GPS4小时，默认下载星历的时间为1小时，即一小时内只会下载一次
        -- debug=true,    --是否输出调试信息
        -- uart=2,    --使用的串口,780EGH和8000默认串口2
        -- uartbaud=115200,    --串口波特率，780EGH和8000默认115200
        -- bind=1, --绑定uart端口进行GNSS数据读取，是否设置串口转发，指定串口号
        -- rtc=false    --定位成功后自动设置RTC true开启，flase关闭
    }
    gnss.setup(gnssotps)
    sys.timerLoopStart(timer1,60000)
    gnss.open(gnss.TIMER,{tag="MODE1",val=20,cb=mode1_cb})
    -- gpio.close(23)--此脚为gnss备电脚，功能是热启动和保存星历文件，关掉会没有热启动，常开功耗会增高
    -- gpio.close(33) -- 如果功耗偏高，开始尝试关闭WAKEUPPAD1
    -- --关闭USB以后可以降低约150ua左右的功耗，如果不需要USB可以关闭
    pm.power(pm.USB, false)

end

sys.taskInit(gnss_fnc)