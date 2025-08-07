--[[
@module  psm
@summary gnss使用psm测试功能模块
@version 1.0
@date    2025.07.27
@author  李源龙
@usage
使用Air8000核心板，外接GPS天线，开启定位，获取到定位发送到服务器上面，然后启动一个60s的定时器唤醒PSM+模式
模块开启定位，然后定位成功获取到经纬度发送到服务器上面，然后进入PSM+模式，等待唤醒
]]
pm.power(pm.WORK_MODE, 0) 
local lat,lng


local server_ip = "112.125.89.8" 
local server_port = 47523 -- 换成自己的
local period = 3 * 60 * 60 * 1000 -- 3小时唤醒一次

local reason, slp_state = pm.lastReson() -- 获取唤醒原因
log.info("wakeup state", pm.lastReson())
local libnet = require "libnet"

local d1Name = "D1_TASK"
local function netCB(msg)
    log.info("未处理消息", msg[1], msg[2], msg[3], msg[4])
end

local function testTask(ip, port)
    local txData
    if reason == 0 then
        txData = "normal wakeup,"..string.format('{"lat":%5f,"lng":%5f}', lat, lng)
    elseif reason == 1 then
        txData = "timer wakeup,"..string.format('{"lat":%5f,"lng":%5f}', lat, lng)
    elseif reason == 2 then
        txData = "pad wakeup,"..string.format('{"lat":%5f,"lng":%5f}', lat, lng)
    elseif reason == 3 then
        txData = "uart1 wakeup,"..string.format('{"lat":%5f,"lng":%5f}', lat, lng)
    end
    if slp_state > 0 then
        mobile.flymode(0, false) -- 退出飞行模式，进入psm+前进入飞行模式，唤醒后需要主动退出
    end


    local netc, needBreak
    local result, param, is_err
    netc = socket.create(nil, d1Name)
    socket.debug(netc, false)
    socket.config(netc) 
    local retry = 0
    while retry < 3 do
        log.info(rtos.meminfo("sys"))
        result = libnet.waitLink(d1Name, 0, netc)
        result = libnet.connect(d1Name, 5000, netc, ip, port)
        if result then
            log.info("服务器连上了")
            result, param = libnet.tx(d1Name, 15000, netc, txData)
            if not result then
                log.info("服务器断开了", result, param)
                break
            else
                needBreak = true
            end
        else
            log.info("服务器连接失败")
        end
        libnet.close(d1Name, 5000, netc)
        retry = retry + 1
        if needBreak then
            break
        end
    end

    uart.setup(1, 9600) -- 配置uart1，外部唤醒用
    
    -- 配置GPIO以达到最低功耗的目的
	-- gpio.close(23) --此脚为gnss备电脚，功能是热启动和保存星历文件，关掉会没有热启动，常开功耗会增高

    pm.dtimerStart(3, period) -- 启动深度休眠定时器

    mobile.flymode(0, true) -- 启动飞行模式，规避可能会出现的网络问题
    pm.power(pm.WORK_MODE, 3) -- 进入极致功耗模式

    sys.wait(15000) -- demo演示唤醒时间是三十分钟，如果15s后模块重启，则说明进入极致功耗模式失败，
    log.info("进入极致功耗模式失败，尝试重启")
    rtos.reboot()
end

local function mode1_cb(tag)
    log.info("TAGmode1_cb+++++++++",tag)
    local  rmc=gnss.getRmc(0)
    log.info("nmea", "rmc", json.encode(gnss.getRmc(0)))
    lat,lng=rmc.lat,rmc.lng
    sysplus.taskInitEx(testTask, d1Name, netCB, server_ip, server_port)
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
        ----定位速度慢，大概35S左右，所以默认开启，如果可以接受下一次定位是冷启动，可以把agps_autoopen设置成false
        ----需要注意的是热启动在定位成功之后，需要再开启3s左右才能保证本次的星历获取完成，如果对定位速度有要求，建议这么处理
        -- agps_autoopen=false 
    }
    gnss.setup(gnssotps)
    gnss.open(gnss.TIMERORSUC,{tag="MODE1",val=60,cb=mode1_cb})
end

sys.taskInit(gnss_fnc)