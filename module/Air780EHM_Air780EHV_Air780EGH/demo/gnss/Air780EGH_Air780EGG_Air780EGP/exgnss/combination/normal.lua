--[[
@module  normal
@summary gnss正常测试功能模块
@version 1.0
@date    2025.07.27
@author  李源龙
@usage
使用Air780EGH核心板，外接GPS天线，定位然后发送经纬度数据给服务器，
起一个60s定位一次的定时器，模块120s一定位，然后定位成功获取到经纬度发送到服务器上面
如果GNSS没有定位成功则获取基站/wifi定位，用付费的基站/wifi定位服务，需要申请项目id和秘钥
不用免费的是因为当前免费的基站定位服务2小时只可以获取一次，测试情况下可以，实际项目运用大概率不符合需求
]]

tcp_client_main=require("tcp_client_main")

local airlbs=require("airlbs")

local timeout = 10 -- 扫描基站/wifi 做 基站/wifi定位 的超时时间，最小5S,最大60S

--  此服务为收费服务，需自行联系销售申请或者在 https://iot.openluat.com/finance/order 购买

--  以下为合宙LBS平台开通的项目id和秘钥
--  以下项目密钥和id请根据实际项目进行修改，https://iot.openluat.com/lbs/bs 在此网址中我的项目下
local airlbs_project_id = "此处换成自己的项目id"
local airlbs_project_key = "此处换成自己的项目key"


--多基站+多wifi定位
local function airlbs_multi_cells_wifi_task_func()
    while not socket.adapter(socket.dft()) do
        log.warn("airlbs_multi_cells_wifi_func", "wait IP_READY", socket.dft())
        -- 在此处阻塞等待默认网卡连接成功的消息"IP_READY"
        -- 或者等待1秒超时退出阻塞等待状态;
        -- 注意：此处的1000毫秒超时不要修改的更长；
        -- 因为当使用exnetif.set_priority_order配置多个网卡连接外网的优先级时，会隐式的修改默认使用的网卡
        -- 当exnetif.set_priority_order的调用时序和此处的socket.adapter(socket.dft())判断时序有可能不匹配
        -- 此处的1秒，能够保证，即使时序不匹配，也能1秒钟退出阻塞状态，再去判断socket.adapter(socket.dft())
        sys.waitUntil("IP_READY", 1000)
    end

    -- 检测到了IP_READY消息
    log.info("airlbs_multi_cells_wifi_func", "recv IP_READY", socket.dft())

    socket.sntp() --进行NTP授时
    sys.waitUntil("NTP_UPDATE", 1000)

    -- 如需wifi定位,需要硬件以及固件支持wifi扫描功能
    local wifi_info = nil
    if wlan then
        wlan.init()--初始化wlan
        wlan.scan()--扫描wifi
        sys.waitUntil("WLAN_SCAN_DONE", timeout * 1000)--等待扫描完成
        wifi_info = wlan.scanResult()--获取扫描结果
        log.info("scan", "wifi_info", #wifi_info)--打印扫描结果
    end
    local result, data = airlbs.request({
        project_id = airlbs_project_id,-- 项目ID
        project_key = airlbs_project_key,-- 项目密钥
        wifi_info = wifi_info,-- wifi信息
        timeout = timeout * 1000,-- 实际的超时时间(单位：ms)
    })
    if result then
        local data_str = json.encode(data)
        log.info("airlbs多基站+多wifi定位返回的经纬度数据为", data_str)-- 解析经纬度
        local lat = data_str:match("\"lat\":([0-9.-]+)")-- 匹配lat
        log.info("airlbs", "lat", lat)-- 打印lat
        local lng = data_str:match("\"lng\":([0-9.-]+)")-- 匹配lng
        log.info("airlbs", "lng", lng)-- 打印lng
        local data=string.format('{"lat":%5f,"lng":%5f}', lat, lng)
        sys.publish("SEND_DATA_REQ", "gnssnormal", data) --发送数据到服务器
    else        
        log.warn("请检查project_id和project_key")-- 打印提示信息
    end
end

local function normal_cb(tag)
    log.info("TAGmode1_cb+++++++++",tag)
    if exgnss.is_fix() then
        local  rmc=exgnss.rmc(0)    --获取rmc数据
        log.info("nmea", "rmc", json.encode(exgnss.rmc(0)))
        local data=string.format('{"lat":%5f,"lng":%5f}', rmc.lat, rmc.lng)
        sys.publish("SEND_DATA_REQ", "gnssnormal", data) --发送数据到服务器
    else
        --GNSS定位失败，开启基站+WIFI定位，获取经纬度，需要注意的是，获取频率需要根据付费的时间来决定，否则会获取失败
        sys.taskInit(airlbs_multi_cells_wifi_task_func)
    end
end

local function normal_open()
    exgnss.open(exgnss.TIMERORSUC,{tag="normal",val=60,cb=normal_cb}) --打开一个60s的TIMERORSUC应用，该模式定位成功关闭
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
        -- auto_open=false,
        -- 定位频率，指gnss每秒输出多少次的定位数据，1hz=1次/秒，默认1hz，可选值：1/2/4/5
        -- hz=1,
    }
    exgnss.setup(gnssotps)  --配置GNSS参数
    exgnss.open(exgnss.TIMER,{tag="normal",val=60,cb=normal_cb}) --打开一个60s的TIMERORSUC应用，该模式定位成功关闭
    -- sys.timerLoopStart(normal_open,120000)       --每120s开启一次GNSS
    
end

sys.taskInit(gnss_fnc)