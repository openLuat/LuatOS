--[[
@module  normal
@summary gnss正常测试功能模块
@version 1.0
@date    2025.07.27
@author  李源龙
@usage
使用Air8000整机开发板，外接GPS天线，定位然后发送经纬度数据给服务器，
起一个60s定位一次的定时器，模块60s一定位，然后定位成功获取到经纬度发送到服务器上面
]]

tcp_client_main=require("tcp_client_main")

local function normal_cb(tag)
    log.info("TAGmode1_cb+++++++++",tag)
    local  rmc=exgnss.rmc(0)    --获取rmc数据
    log.info("nmea", "rmc", json.encode(exgnss.rmc(0)))
    local data=string.format('{"lat":%5f,"lng":%5f}', rmc.lat, rmc.lng)
    sys.publish("SEND_DATA_REQ", "gnssnormal", data) --发送数据到服务器
end
local function normal_open()
    exgnss.open(exgnss.TIMERORSUC,{tag="normal",val=60,cb=normal_cb}) --打开一个60s的TIMERORSUC应用，该模式定位成功关闭
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
        ----因为GNSS使用辅助定位的逻辑，是模块下载星历文件，然后把数据发送给GNSS芯片，
        ----芯片解析星历文件需要10-30s，默认GNSS会开启20s，该逻辑如果不执行，会导致下一次GNSS开启定位是冷启动，
        ----定位速度慢，大概35S左右，所以默认开启，如果可以接受下一次定位是冷启动，可以把auto_open设置成false
        ----需要注意的是热启动在定位成功之后，需要再开启3s左右才能保证本次的星历获取完成，如果对定位速度有要求，建议这么处理
        -- auto_open=false 
    }
    exgnss.setup(gnssotps)  --配置GNSS参数
    exgnss.open(exgnss.TIMERORSUC,{tag="normal",val=60,cb=normal_cb}) --打开一个60s的TIMERORSUC应用，该模式定位成功关闭
    sys.timerLoopStart(normal_open,60000)       --每60s开启一次GNSS
    
end

sys.taskInit(gnss_fnc)