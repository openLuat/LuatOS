--[[
@module  da221gnss
@summary 利用加速度传感器da221实现中断触发gnss定位
@version 1.0
@date    2025.08.01
@author  李源龙
@usage
使用Air8000利用内置的da221加速度传感器实现中断触发gnss定位
]]
gnss=require("gnss")
tcp=require("tcp")
da221=require("da221")

local intPin=gpio.WAKEUP2
local tid
local function mode1_cb(tag)
    log.info("TAGmode1_cb+++++++++",tag)
    local  rmc=gnss.getRmc(0)
    log.info("nmea", "rmc", json.encode(gnss.getRmc(0)))
    tcp.latlngfnc(rmc.lat,rmc.lng)
end
local function timer1()
    gnss.close(gnss.DEFAULT,{tag="MODE1"})
    sys.timerStop(tid)
end

local function ind()
    log.info("int", gpio.get(intPin))
    if gpio.get(intPin) == 1 then
        sys.timerStart(timer1,10000)
        local x,y,z =  da221.read_xyz()      --读取x，y，z轴的数据
        log.info("x", x..'g', "y", y..'g', "z", z..'g')
        if gnss.openres()~=true then
            log.info("nmea", "openres", "false")
            gnss.open(gnss.DEFAULT,{tag="MODE1",cb=mode1_cb}) 
            tid=sys.timerLoopStart(mode1_cb, 5000)
        else
            log.info("nmea", "openres", "true")
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
        ----定位速度慢，大概35S左右，所以默认开启，如果可以接受下一次定位是冷启动，可以把agps_autoopen设置成false
        ----需要注意的是热启动在定位成功之后，需要再开启3s左右才能保证本次的星历获取完成，如果对定位速度有要求，建议这么处理
        -- agps_autoopen=false 
    }
    gnss.setup(gnssotps)
    --1、静态/微动检测，使用场景：微振动检测、手势识别；
    --2、常规运动监测，使用场景：运动监测、车载设备；
    --3、高动态冲击检测，使用场景：碰撞检测、工业冲击
    da221.open(1)
    gpio.debounce(intPin, 100)
    gpio.setup(intPin, ind)

end

sys.taskInit(gnss_fnc)