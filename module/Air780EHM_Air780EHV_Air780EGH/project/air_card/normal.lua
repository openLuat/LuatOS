--[[
@module  normal
@summary gnss正常测试功能模块
@version 1.0
@date    2025.07.27
@author  李源龙
@usage
使用Air780EGH核心板，外接GPS天线，起一个60s定位一次的定时器，模块60s一定位，然后定位成功获取到经纬度发送到服务器上面
]]
exgnss = require("exgnss")
gps = {}
gps_power = false
local function mode2_cb(tag)
end
-- 获取位置
function gps.getloc()
    local fix = exgnss.is_fix()
    local rmc=exgnss.rmc(2)
    log.info("位置",rmc.lat,rmc.lng)
    return fix,rmc
end
--打开gps
function gps.open()
    if not gps_power then
        gps_power = true
        exgnss.open(exgnss.DEFAULT,{tag="MODE2",cb=mode2_cb})
    end
end
--关闭gps
function gps.close()
    if gps_power then
        gps_power = false
        exgnss.close_all()
    end
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
    exgnss.setup(gnssotps)
    gps.open()
    -- sys.timerLoopStart(timer1,60000)
end


sys.taskInit(gnss_fnc)

return gps