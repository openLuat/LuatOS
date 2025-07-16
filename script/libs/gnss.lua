--[[
@module gnss
@summary gnss拓展库
@version 1.0
@date    2025.07.16
@author  李源龙
@usage
-- 用法实例
-- 提醒: 本库输出的坐标,均为 WGS84 坐标系
-- 如需要在国内地图使用, 要转换成对应地图的坐标系, 例如 GCJ02 BD09
-- 相关链接: https://lbsyun.baidu.com/index.php?title=coordinate
-- 相关链接: https://www.openluat.com/GPS-Offset.html

--关于gnss的三种应用场景：
gnss.DEFAULT:
--- gnss应用模式1.
--
-- 打开gnss后，gnss定位成功时，如果有回调函数，会调用回调函数
--
-- 使用此应用模式调用gnss.open打开的“gnss应用”，必须主动调用gnss.close或者gnss.closeAll才能关闭此“gnss应用”,主动关闭时，即使有回调函数，也不会调用回调函数
-- 通俗点说就是一直打开，除非自己手动关闭掉

gnss.TIMERORSUC:
--- gnss应用模式2.
--
-- 打开gnss后，如果在gnss开启最大时长到达时，没有定位成功，如果有回调函数，会调用回调函数，然后自动关闭此“gnss应用”
--
-- 打开gnss后，如果在gnss开启最大时长内，定位成功，如果有回调函数，会调用回调函数，然后自动关闭此“gnss应用”
--
-- 打开gnss后，在自动关闭此“gnss应用”前，可以调用gnss.close或者gnss.closeAll主动关闭此“gnss应用”，主动关闭时，即使有回调函数，也不会调用回调函数
-- 通俗点说就是设置规定时间打开，如果规定时间内定位成功就会关闭此应用，如果没有定位成功，时间到了也会关闭此应用

gnss.TIMER:
--- gnss应用模式3.
--
-- 打开gnss后，在gnss开启最大时长时间到达时，无论是否定位成功，如果有回调函数，会调用回调函数，然后自动关闭此“gnss应用”
--
-- 打开gnss后，在自动关闭此“gnss应用”前，可以调用gnss.close或者gnss.closeAll主动关闭此“gnss应用”，主动关闭时，即使有回调函数，也不会调用回调函数
-- 通俗点说就是设置规定时间打开，无论是否定位成功，到了时间都会关闭此应用，和第二种的区别在于定位成功之后不会关闭，到时间之后才会关闭

gnss=require("gnss")    

function test1Cb(val)
    log.info("TAG+++++++++",val)
    log.info("nmea", "rmc", json.encode(gnss.getRmc(2)))
end

function test2Cb(val)
    log.info("TAG+++++++++",val)
    log.info("nmea", "rmc", json.encode(gnss.getRmc(2)))
end

sys.taskInit(function()
    local gnssotps={
        gnssmode=1, --1为卫星全定位，2为单北斗
        agps_enable=true,    --是否使用AGPS，开启AGPS后定位速度更快，会访问服务器下载星历，星历时效性为北斗1小时，GPS4小时，默认下载星历的时间为1小时，即一小时内只会下载一次
        debug=true,    --是否输出调试信息
        -- uart=2,    --使用的串口,780EGH和8000默认串口2
        -- uartbaud=115200,    --串口波特率，780EGH和8000默认115200
        -- bind=1, --绑定uart端口进行GNSS数据读取，是否设置串口转发，指定串口号
        -- rtc=false    --定位成功后自动设置RTC true开启，flase关闭
    }
    gnss.setup(gnssotps)
    gnss.open(gnss.TIMER,{tag="TEST1",val=60,cb=test1Cb})
    gnss.open(gnss.TIMERORSUC,{tag="TEST3",val=60,cb=test2Cb})
    gnss.open(gnss.DEFAULT,{tag="TEST2",cb=test2Cb})
    sys.wait(40000)
    log.info("关闭定时器的")
    gnss.close(gnss.TIMER,{tag="TEST1"})
    log.info("定时器状态1",gnss.isActive(gnss.TIMER,{tag="TEST1"}))
    log.info("定时器状态2",gnss.isActive(gnss.DEFAULT,{tag="TEST2"}))
    log.info("定时器状态3",gnss.isActive(gnss.TIMERORSUC,{tag="TEST3"}))
    sys.wait(10000)
    gnss.closeAll()
    log.info("定时器状态1",gnss.isActive(gnss.TIMER,{tag="TEST1"}))
    log.info("定时器状态2",gnss.isActive(gnss.DEFAULT,{tag="TEST2"}))
    log.info("定时器状态3",gnss.isActive(gnss.TIMERORSUC,{tag="TEST3"}))
end)

sys.subscribe("GNSS_STATE", function(event, ticks)
    -- event取值有
    -- FIXED 定位成功
    -- LOSE  定位丢失
    -- ticks是事件发生的时间,一般可以忽略
    log.info("gnss", "state", event, ticks)
end)

]]
local gnss = {}
--gnss开启标志，true表示开启状态，false或者nil表示关闭状态
local openFlag
--gnss定位标志，true表示，其余表示未定位
local fixFlag=nil

--串口配置
local uartBaudrate = 115200
local uartID = 2

--gnss 的串口线程是否在工作；
local taskFlag=false

--agps操作，联网访问服务器获取星历数据
local function _agps()
    -- 首先, 发起位置查询
local lat, lng
sys.waitUntil("net_ready")
if mobile then
    mobile.reqCellInfo(6)
    sys.waitUntil("CELL_INFO_UPDATE", 6000)
    local lbsLoc2 = require("lbsLoc2")
    lat, lng = lbsLoc2.request(5000)
    -- local lat, lng, t = lbsLoc2.request(5000, "bs.openluat.com")
    log.info("lbsLoc2", lat, lng)
    if lat and lng then
        lat = tonumber(lat)
        lng = tonumber(lng)
        log.info("lbsLoc2", lat, lng)
        -- 转换单位
        local lat_dd,lat_mm = math.modf(lat)
        local lng_dd,lng_mm = math.modf(lng)
        lat = lat_dd * 100 + lat_mm * 60
        lng = lng_dd * 100 + lng_mm * 60
    end
elseif wlan then
    -- wlan.scan()
    -- sys.waitUntil("WLAN_SCAN_DONE", 5000)
end
if not lat then
    -- 获取最后的本地位置
    local locStr = io.readFile("/hxxtloc")
    if locStr then
        local jdata = json.decode(locStr)
        if jdata and jdata.lat then
            lat = jdata.lat
            lng = jdata.lng
        end
    end
end
-- 然后, 判断星历时间和下载星历
local now = os.time()
local agps_time = tonumber(io.readFile("/hxxt_tm") or "0") or 0
log.info("os.time",now)
log.info("agps_time",agps_time)
if now - agps_time > 3600 then
    local url = gnss.opts.url
    if not gnss.opts.url then
        if gnss.opts.sys and 2 == gnss.opts.sys then
            -- 单北斗
            url = "http://download.openluat.com/9501-xingli/HXXT_BDS_AGNSS_DATA.dat"
        else
            url = "http://download.openluat.com/9501-xingli/HXXT_GPS_BDS_AGNSS_DATA.dat"
        end
    end
    local code = http.request("GET", url, nil, nil, {dst="/hxxt.dat"}).wait()
    if code and code == 200 then
        log.info("gnss.opts", "下载星历成功", url)
        io.writeFile("/hxxt_tm", tostring(now))
    else
        log.info("gnss.opts", "下载星历失败", code)
    end
else
    log.info("gnss.opts", "星历不需要更新", now - agps_time)
end

local gps_uart_id = uartID

-- 写入星历
local agps_data = io.readFile("/hxxt.dat")
if agps_data and #agps_data > 1024 then
    log.info("gnss.opts", "写入星历数据", "长度", #agps_data)
    for offset=1,#agps_data,512 do
        log.info("gnss", "AGNSS", "write >>>", #agps_data:sub(offset, offset + 511))
        uart.write(gps_uart_id, agps_data:sub(offset, offset + 511))
        sys.wait(100) -- 等100ms反而更成功
    end
    -- uart.write(gps_uart_id, agps_data)
else
    log.info("gnss.opts", "没有星历数据")
    return
end

-- 写入参考位置
-- "lat":23.4068813,"min":27,"valid":true,"day":27,"lng":113.2317505
if not lat or not lng then
    -- lat, lng = 23.4068813, 113.2317505
    log.info("gnss.opts", "没有GPS坐标", lat, lng)
    return --暂时不写入参考位置
end
if socket.sntp then
    socket.sntp()
    sys.waitUntil("NTP_UPDATE", 1000)
end
local date = os.date("!*t")
if date.year > 2023 then
    local str = string.format("$AIDTIME,%d,%d,%d,%d,%d,%d,000", date["year"], date["month"], date["day"],
        date["hour"], date["min"], date["sec"])
    log.info("gnss.opts", "参考时间", str)
    uart.write(gps_uart_id, str .. "\r\n")
    sys.wait(20)
end

local str = string.format("$AIDPOS,%.7f,%s,%.7f,%s,1.0\r\n",
lat > 0 and lat or (0 - lat), lat > 0 and 'N' or 'S',
lng > 0 and lng or (0 - lng), lng > 0 and 'E' or 'W')
log.info("gnss.opts", "写入AGPS参考位置", str)
uart.write(gps_uart_id, str)

-- 结束
gnss.opts.agps_tm = now
end

--执行agps操作判断
local function agps(force)
    -- 如果不是强制写入AGPS信息, 而且是已经定位成功的状态,那就没必要了
    if not force and libgnss.isFix() then return end
    -- 先判断一下时间
    local now = os.time()
    if force or not gnss.opts.agps_tm or now - gnss.opts.agps_tm > 3600 then
        -- 执行AGPS
        log.info("gnss.opts", "开始执行AGPS")
        sys.taskInit(_agps)
    else
        log.info("gnss.opts", "暂不需要写入AGPS")
    end
end

--打开gnss，内部函数使用，不推荐给脚本层使用
local function _open()
    if openFlag then return end
    libgnss.clear() -- 清空数据,兼初始化
    uart.setup(uartID, uartBaudrate)
    -- pm.power(pm.GPS, false)
    pm.power(pm.GPS, true)
    if gnss.opts.gnssmode==1 then
        --默认全开启
        log.info("全卫星开启")
        elseif gnss.opts.gnssmode==2 then
        --默认开启单北斗
        sys.timerStart(function()
            uart.write(uartID, "$CFGSYS,h10\r\n")
        end,200)
        log.info("单北斗开启")
    end
    if gnss.opts.debug==true then
        log.info("debug开启")
        libgnss.debug(true)
    elseif gnss.opts.debug==false then
        log.info("debug关闭")
        libgnss.debug(false)
    end
    if type(gnss.opts.bind)=="number"  then
        log.info("绑定bind事件")
        libgnss.bind(uartID,gnss.opts.bind)
    else
        libgnss.bind(uartID)
    end
    if gnss.opts.rtc==true then
        log.info("rtc开启")
        libgnss.rtcAuto(true)
    elseif gnss.opts.rtc==false then
        log.info("rtc关闭")
        libgnss.rtcAuto(false)
    end
    if gnss.opts.agps_enable==true then
        log.info("agps开启")
        agps()
    end
    --设置输出VTG内容
    sys.timerStart(function()
        uart.write(uartID,"$CFGMSG,0,5,1,1\r\n")
    end,500)
    openFlag = true
    sys.publish("GPS_STATE","OPEN")
    log.info("gnss._open")
end

--关闭gnss，内部函数使用，不推荐给脚本层使用
local function _close()
    if not openFlag then return end
    pm.power(pm.GPS, false)
    uart.close(uartID)
    libgnss.clear()
    openFlag = false
    fixFlag = false
    sys.publish("GPS_STATE","CLOSE",fixFlag)    
    log.info("gnss._close")
end


--- gnss应用模式1.
--
-- 打开gnss后，gnss定位成功时，如果有回调函数，会调用回调函数
--
-- 使用此应用模式调用gnss.open打开的“gnss应用”，必须主动调用gnss.close或者gnss.closeAll才能关闭此“gnss应用”,主动关闭时，即使有回调函数，也不会调用回调函数
gnss.DEFAULT = 1
--- gnss应用模式2.
--
-- 打开gnss后，如果在gnss开启最大时长到达时，没有定位成功，如果有回调函数，会调用回调函数，然后自动关闭此“gnss应用”
--
-- 打开gnss后，如果在gnss开启最大时长内，定位成功，如果有回调函数，会调用回调函数，然后自动关闭此“gnss应用”
--
-- 打开gnss后，在自动关闭此“gnss应用”前，可以调用gnss.close或者gnss.closeAll主动关闭此“gnss应用”，主动关闭时，即使有回调函数，也不会调用回调函数
gnss.TIMERORSUC = 2
--- gnss应用模式3.
--
-- 打开gnss后，在gnss开启最大时长时间到达时，无论是否定位成功，如果有回调函数，会调用回调函数，然后自动关闭此“gnss应用”
--
-- 打开gnss后，在自动关闭此“gnss应用”前，可以调用gnss.close或者gnss.closeAll主动关闭此“gnss应用”，主动关闭时，即使有回调函数，也不会调用回调函数
gnss.TIMER = 3

--“gnss应用”表
local tList = {}

--[[
函数名：delItem
功能  ：从“gnss应用”表中删除一项“gnss应用”，并不是真正的删除，只是设置一个无效标志
参数  ：
        mode：gnss应用模式
        para：
            para.tag：“gnss应用”标记
            para.val：gnss开启最大时长
            para.cb：回调函数
返回值：无
]]
local function delItem(mode,para)
    for i=1,#tList do
        --标志有效 并且 gnss应用模式相同 并且 “gnss应用”标记相同
        if tList[i].flag and tList[i].mode==mode and tList[i].para.tag==para.tag then
            --设置无效标志
            tList[i].flag,tList[i].delay = false
            break
        end
    end
end
sys.taskInit(function()
    sys.waitUntil("IP_READY")
    log.info("已联网")
    sys.publish("net_ready")
end)



--[[
函数名：addItem
功能  ：新增一项“gnss应用”到“gnss应用”表
参数  ：
        mode：gnss应用模式
        para：
            para.tag：“gnss应用”标记
            para.val：gnss开启最大时长
            para.cb：回调函数
返回值：无
]]
local function addItem(mode,para)
    --删除相同的“gnss应用”
    delItem(mode,para)
    local item,i,fnd = {flag=true, mode=mode, para=para}
    --如果是TIMERORSUC或者TIMER模式，初始化gnss工作剩余时间
    if mode==gnss.TIMERORSUC or mode==gnss.TIMER then item.para.remain = para.val end
    for i=1,#tList do
        --如果存在无效的“gnss应用”项，直接使用此位置
        if not tList[i].flag then
            tList[i] = item
            fnd = true
            break
        end
    end
    --新增一项
    if not fnd then table.insert(tList,item) end
end

--退出GNSS定时器
local function existTimerItem()
    for i=1,#tList do
        if tList[i].flag and (tList[i].mode==gnss.TIMERORSUC or tList[i].mode==gnss.TIMER or tList[i].para.delay) then return true end
    end
end

--GNSS定时器
local function timerFnc()
    for i=1,#tList do
        if tList[i].flag then
            log.info("gnss.timerFnc@"..i,tList[i].mode,tList[i].para.tag,tList[i].para.val,tList[i].para.remain,tList[i].para.delay)
            local rmn,dly,md,cb = tList[i].para.remain,tList[i].para.delay,tList[i].mode,tList[i].para.cb

            if rmn and rmn>0 then
                tList[i].para.remain = rmn-1
            end
            if dly and dly>0 then
                tList[i].para.delay = dly-1
            end
            rmn = tList[i].para.remain

            if libgnss.isFix() and md==gnss.TIMER and rmn==0 and not tList[i].para.delay then
                tList[i].para.delay = 1
            end
            dly = tList[i].para.delay
            if libgnss.isFix() then
                if dly and dly==0 then
                    if cb then cb(tList[i].para.tag) end
                    if md == gnss.DEFAULT then
                        tList[i].para.delay = nil
                    else
                        gnss.close(md,tList[i].para)
                    end
                end
            else
                if rmn and rmn == 0 then
                    if cb then cb(tList[i].para.tag) end
                    gnss.close(md,tList[i].para)
                end
            end
        end
    end
    if existTimerItem() then sys.timerStart(timerFnc,1000) end
end

--[[
函数名：statInd
功能  ：处理gnss定位成功的消息
参数  ：
        evt：gnss消息类型
返回值：无
]]
local function statInd(evt)
    --定位成功的消息
    if evt == "FIXED" then
        fixFlag = true
        for i=1,#tList do
            log.info("gnss.statInd@"..i,tList[i].flag,tList[i].mode,tList[i].para.tag,tList[i].para.val,tList[i].para.remain,tList[i].para.delay,tList[i].para.cb)
            if tList[i].flag then
                if tList[i].mode ~= gnss.TIMER then
                    tList[i].para.delay = 1
                    if tList[i].mode == gnss.DEFAULT then
                        if existTimerItem() then sys.timerStart(timerFnc,1000) end
                    end
                end
            end
        end
    end
end


--[[
设置gnss定位参数
@api gnss.setup(opts)
@table opts gnss定位参数，可选值gnssmode:定位卫星模式，1为卫星全定位，2为单北斗，默认为卫星全定位
agps_enable:是否启用AGPS，true为启用，false为不启用，默认为false
debug:是否输出调试信息到luatools，true为输出，false为不输出，默认为false
uart:GNSS串口配置，780EGH和8000默认为uart2，可不填
uartbaud:GNSS串口波特率，780EGH和8000默认为115200，可不填
bind:绑定uart端口进行GNSS数据读取，是否设置串口转发，指定串口号，不需要转发可不填
rtc:定位成功后自动设置RTC true开启，flase关闭，默认为flase，不需要可不填
@return nil
@usage
local gnssotps={
        gnssmode=1, --1为卫星全定位，2为单北斗
        agps_enable=true,    --是否使用AGPS，开启AGPS后定位速度更快，会访问服务器下载星历，星历时效性为北斗1小时，GPS4小时，默认下载星历的时间为1小时，即一小时内只会下载一次
        debug=true,    --是否输出调试信息
        -- uart=2,    --使用的串口,780EGH和8000默认串口2
        -- uartbaud=115200,    --串口波特率，780EGH和8000默认115200
        -- bind=1, --绑定uart端口进行GNSS数据读取，是否设置串口转发，指定串口号
        -- rtc=false    --定位成功后自动设置RTC true开启，flase关闭
    }
    gnss.setup(gnssotps)
]]
function gnss.setup(opts)
    gnss.opts=opts
    if hmeta.model()=="780EGH" or hmeta.model()=="Air8000" then
        uartID=2
        uartBaudrate=115200
    else
        if gnss.opts.uartid then
            uartID=gnss.opts.uartid
        else
            uartID=2    
        end
        if gnss.opts.uartbaud then
            uartBaudrate=gnss.opts.uartbaud
        else
            uartBaudrate=115200
        end
    end   
end

--[[
打开一个“gnss应用”
@api gnss.open(mode,para)
@number mode gnss应用模式，支持gnss.DEFAULT，gnss.TIMERORSUC，gnss.TIMER三种
@param para table类型，gnss应用参数,para.tag：string类型，gnss应用标记,para.val：number类型，gnss应用开启最大时长，mode参数为gnss.TIMERORSUC或者gnss.TIMER时，此值才有意义；使用close接口时，不需要传入此参数,para.cb：gnss应用结束时的回调函数，回调函数的调用形式为para.cb(para.tag)；使用close接口时，不需要传入此参数
@return nil
@usage
-- “gnss应用”：指的是使用gnss功能的一个应用
-- 例如，假设有如下3种需求，要打开gnss，则一共有3个“gnss应用”：
-- “gnss应用1”：每隔1分钟打开一次gnss
-- “gnss应用2”：设备发生震动时打开gnss
-- “gnss应用3”：收到一条特殊短信时打开gnss
-- 只有所有“gnss应用”都关闭了，才会去真正关闭gnss
-- 每个“gnss应用”打开或者关闭gnss时，最多有4个参数，其中 gnss应用模式和gnss应用标记 共同决定了一个唯一的“gnss应用”：
-- 1、gnss应用模式(必选)
-- 2、gnss应用标记(必选)
-- 3、gnss开启最大时长[可选]
-- 4、回调函数[可选]
-- 例如gnss.open(gnss.TIMERORSUC,{tag="TEST",val=120,cb=testgnssCb})
-- gnss.TIMERORSUC为gnss应用模式，"TEST"为gnss应用标记，120秒为gnss开启最大时长，testgnssCb为回调函数
gnss.open(gnss.DEFAULT,{tag="TEST1",cb=test1Cb})
gnss.open(gnss.TIMERORSUC,{tag="TEST2",val=60,cb=test2Cb})
gnss.open(gnss.TIMER,{tag="TEST3",val=120,cb=test3Cb})
]]
function gnss.open(mode,para)
    assert((para and type(para) == "table" and para.tag and type(para.tag) == "string"),"gnss.open para invalid")
    log.info("gnss.open",mode,para.tag,para.val,para.cb)
    --如果gnss定位成功
    if libgnss.isFix() then
        if mode~=gnss.TIMER then
            --执行回调函数
            if para.cb then para.cb(para.tag) end
            if mode==gnss.TIMERORSUC then return end
        end
    end
    addItem(mode,para)
    --真正去打开gnss
    _open()
    --启动1秒的定时器
    if existTimerItem() and not sys.timerIsActive(timerFnc) then
        sys.timerStart(timerFnc,1000)
    end
end


--[[
关闭一个“gnss应用”，只是从逻辑上关闭一个gnss应用，并不一定真正关闭gnss，是有所有的gnss应用都处于关闭状态，才会去真正关闭gnss
@api gnss.close()
@number mode gnss应用模式，支持gnss.DEFAULT，gnss.TIMERORSUC，gnss.TIMER三种
@param para table类型，gnss应用参数,para.tag：string类型，gnss应用标记,para.val：number类型，gnss应用开启最大时长，mode参数为gnss.TIMERORSUC或者gnss.TIMER时，此值才有意义；使用close接口时，不需要传入此参数,para.cb：gnss应用结束时的回调函数，回调函数的调用形式为para.cb(para.tag)；使用close接口时，不需要传入此参数
@return nil
@usage
gnss.open(gnss.TIMER,{tag="TEST1",val=60,cb=test1Cb})
gnss.close(gnss.TIMER,{tag="TEST1"})
]]
function gnss.close(mode,para)
    assert((para and type(para)=="table" and para.tag and type(para.tag)=="string"),"gnss.close para invalid")
    log.info("gnss.close",mode,para.tag,para.val,para.cb)
    --删除此“gnss应用”
    delItem(mode,para)
    local valid,i
    for i=1,#tList do
        if tList[i].flag then
            valid = true
        end
    end
    --如果没有一个“gnss应用”有效，则关闭gnss
    if not valid then _close() end
end

--[[
关闭所有“gnss应用”
@api gnss.closeAll()
@return nil
@usage
gnss.open(gnss.TIMER,{tag="TEST1",val=60,cb=test1Cb})
gnss.open(gnss.TIMERORSUC,{tag="TEST3",val=60,cb=test2Cb})
gnss.open(gnss.DEFAULT,{tag="TEST2",cb=test2Cb})
gnss.closeAll()
]]
function gnss.closeAll()
    for i=1,#tList do
        if tList[i].flag and tList[i].para.cb then tList[i].para.cb(tList[i].para.tag) end
        gnss.close(tList[i].mode,tList[i].para)
    end
end

--[[
判断一个“gnss应用”是否处于激活状态
@api gnss.isActive(mode,para)
@number mode gnss应用模式，支持gnss.DEFAULT，gnss.TIMERORSUC，gnss.TIMER三种
@param para table类型，gnss应用参数,para.tag：string类型，gnss应用标记,para.val：number类型，gnss应用开启最大时长，mode参数为gnss.TIMERORSUC或者gnss.TIMER时，此值才有意义；使用close接口时，不需要传入此参数,para.cb：gnss应用结束时的回调函数，回调函数的调用形式为para.cb(para.tag)；使用close接口时，不需要传入此参数,gnss应用模式和gnss应用标记唯一确定一个“gnss应用”，调用本接口查询状态时，mode和para.tag要和gnss.open打开一个“gnss应用”时传入的mode和para.tag保持一致
@return bool result，处于激活状态返回true，否则返回nil
@usage
gnss.open(gnss.TIMER,{tag="TEST1",val=60,cb=test1Cb})
gnss.open(gnss.TIMERORSUC,{tag="TEST3",val=60,cb=test2Cb})
gnss.open(gnss.DEFAULT,{tag="TEST2",cb=test2Cb})
log.info("定时器状态1",gnss.isActive(gnss.TIMER,{tag="TEST1"}))
log.info("定时器状态2",gnss.isActive(gnss.DEFAULT,{tag="TEST2"}))
log.info("定时器状态3",gnss.isActive(gnss.TIMERORSUC,{tag="TEST3"}))
]]
function gnss.isActive(mode,para)
    assert((para and type(para)=="table" and para.tag and type(para.tag)=="string"),"gnss.isActive para invalid")
    for i=1,#tList do
        if tList[i].flag and tList[i].mode==mode and tList[i].para.tag==para.tag then return true end
    end
end

sys.subscribe("GNSS_STATE",statInd)


--[[
当前是否已经定位成功
@api gnss.isFix()
@return boolean   定位成功与否
@usage
log.info("nmea", "isFix", gnss.isFix())
]]
function gnss.isFix()
   return libgnss.isFix()
end


--[[
清除历史定位数据
@api gnss.clear()
@return nil
@usage
gnss.clear()
]]
function gnss.clear()
   libgnss.clear()
end


--[[
获取位置信息
@api gnss.getIntLocation(speed_type)
@number 速度单位,默认是m/h,
0 - m/h 米/小时, 默认值, 整型
1 - m/s 米/秒, 浮点数
2 - km/h 千米/小时, 浮点数
3 - kn/h 英里/小时, 浮点数
@return int lat数据, 格式为 ddddddddd
@return int lng数据, 格式为 ddddddddd
@return int speed数据, 单位米.
@usage
-- 建议用gnss.getRmc(1)
log.info("nmea", "loc", gnss.getIntLocation())
-- 默认 米/小时
log.info("nmea", "loc", gnss.getIntLocation())
-- 米/秒
log.info("nmea", "loc", gnss.getIntLocation(1))
-- 千米/小时
log.info("nmea", "loc", gnss.getIntLocation(2))
-- 英里/小时
log.info("nmea", "loc", gnss.getIntLocation(3))
]]
function gnss.getIntLocation(speed_type)
    return libgnss.getIntLocation(speed_type)
end


--[[
获取原始RMC位置信息
@api gnss.getRmc(data_mode)
@int 坐标类数据的格式, 0-DDMM.MMM格式, 1-DDDDDDD格式, 2-DD.DDDDD格式, 3-原始RMC字符串
@return table 原始rmc数据
@usage
-- 解析nmea
log.info("nmea", "rmc", json.encode(gnss.getRmc(2)))
-- 实例输出
-- {
--     "course":0,
--     "valid":true,   // true定位成功,false定位丢失
--     "lat":23.4067,  // 纬度, 正数为北纬, 负数为南纬
--     "lng":113.231,  // 经度, 正数为东经, 负数为西经
--     "variation":0,  // 地面航向，单位为度，从北向起顺时针计算
--     "speed":0       // 地面速度, 单位为"节"
--     "year":2023,    // 年份
--     "month":1,      // 月份, 1-12
--     "day":5,        // 月份天, 1-31
--     "hour":7,       // 小时,0-23
--     "min":23,       // 分钟,0-59
--     "sec":20,       // 秒,0-59
-- }
]]
function gnss.getRmc(data_mode)
    return libgnss.getRmc(data_mode)
end

--[[
获取原始GSV信息
@api gnss.getGsv()
@return table 原始GSV数据
@usage
-- 解析nmea
log.info("nmea", "gsv", json.encode(gnss.getGsv()))
-- 实例输出
-- {
--     "total_sats":24,      // 总可见卫星数量
--     "sats":[
--         {
--             "snr":27,     // 信噪比
--             "azimuth":278, // 方向角
--             "elevation":59, // 仰角
--             "tp":0,        // 0 - GPS, 1 - BD
--             "nr":4         // 卫星编号
--         },
--         // 这里忽略了22个卫星的信息
--         {
--             "snr":0,
--             "azimuth":107,
--             "elevation":19,
--             "tp":1,
--             "nr":31
--         }
--     ]
-- }
]]
function gnss.getGsv() 
    return libgnss.getGsv() 
end


--[[
获取原始GSA信息
@api gnss.getGsa(data_mode)
@int 模式，默认为0 -所有卫星系统全部输出在一起，1 - 每个卫星系统单独分开输出
@return table 原始GSA数据
@usage
-- 获取
log.info("nmea", "gsa", json.encode(gnss.getGsa(), "11g"))
-- 示例数据(模式0, 也就是默认模式)
--sysid:1为GPS，4为北斗，2为GLONASS，3为Galileo
{"pdop":1.5169999600,"sats":[18,12,25,10,24,23,15,6,24,39,43,16,9,21,13,1,14],"vdop":1.2760000230,"hdop":0.81999999300,"sysid":1,"fix_type":3}

--模式1
   [{"pdop":1.5169999600,"sats":[18,12,25,10,24,23,15],"vdop":1.2760000230,"hdop":0.81999999300,"sysid":1,"fix_type":3},
   {"pdop":1.5169999600,"sats":[6,24,39,43,16,9,21,13,1,14],"vdop":1.2760000230,"hdop":0.81999999300,"sysid":4,"fix_type":3},
   {"pdop":1.5169999600,"sats":{},"vdop":1.2760000230,"hdop":0.81999999300,"sysid":2,"fix_type":3},
   {"pdop":1.5169999600,"sats":{},"vdop":1.2760000230,"hdop":0.81999999300,"sysid":3,"fix_type":3}]
]]

function gnss.getGsa(data_mode)
    return libgnss.getGsa(data_mode)
end


--[[
获取VTA速度信息
@api gnss.getVtg(data_mode)
@int 可选, 3-原始字符串, 不传或者传其他值, 则返回浮点值
@return table 原始VTA数据
@usage
-- 解析nmea
log.info("nmea", "vtg", json.encode(gnss.getVtg()))
-- 示例
{
    "speed_knots":0,        // 速度, 英里/小时
    "true_track_degrees":0,  // 真北方向角
    "magnetic_track_degrees":0, // 磁北方向角
    "speed_kph":0           // 速度, 千米/小时
}

--模式3
log.info("nmea", "vtg", json.encode(gnss.getVtg(3)))
-- 返回值："$GNVTG,0.000,T,,M,0.000,N,0.000,K,A*13\r"
-- 提醒: 在速度<5km/h时, 不会返回方向角
]]
function gnss.getVtg(data_mode)
    return  libgnss.getVtg(data_mode)
end

--获取原始ZDA时间和日期信息
--[[
获取原始ZDA时间和日期信息
@api gnss.getZda()
@return table 原始zda数据
@usage
log.info("nmea", "zda", json.encode(gnss.getZda()))
-- 实例输出
-- {
--     "minute_offset":0,   // 本地时区的分钟, 一般固定输出0
--     "hour_offset":0,     // 本地时区的小时, 一般固定输出0
--     "year":2023         // UTC 年，四位数字
--     "month":1,          // UTC 月，两位，01 ~ 12
--     "day":5,            // UTC 日，两位数字，01 ~ 31
--     "hour":7,           // 小时
--     "min":50,           // 分
--     "sec":14,           // 秒
-- }
]]
function gnss.getZda()
    return  libgnss.getZda()
end

--[[
获取GGA数据
@api gnss.getGga(data_mode)
@int 坐标类数据的格式, 0-DDMM.MMM格式, 1-DDDDDDD格式, 2-DD.DDDDD格式, 3-原始字符串
@return table GGA数据, 若如不存在会返回nil
@usage
local gga = gnss.getGga(2)
if gga then
    log.info("GGA", json.encode(gga, "11g"))
end
--实例输出
-- {
--     "dgps_age":0,             // 差分校正时延，单位为秒
--     "fix_quality":1,          // 定位状态标识 0 - 无效,1 - 单点定位,2 - 差分定位
--     "satellites_tracked":14,  // 参与定位的卫星数量
--     "altitude":0.255,         // 海平面分离度, 或者成为海拔, 单位是米,
--     "hdop":0.0335,            // 水平精度因子，0.00 - 99.99，不定位时值为 99.99
--     "longitude":113.231,      // 经度, 正数为东经, 负数为西经
--     "latitude":23.4067,       // 纬度, 正数为北纬, 负数为南纬
--     "height":0                // 椭球高，固定输出 1 位小数
-- }
]]
function gnss.getGga(data_mode)
    return  libgnss.getGga(data_mode)
end

--[[
获取GLL数据
@api gnss.getGll(data_mode)
@int 坐标类数据的格式, 0-DDMM.MMM格式, 1-DDDDDDD格式, 2-DD.DDDDD格式
@return table GLL数据, 若如不存在会返回nil
@usage
local gll = gnss.getGll(2)
if gll then
    log.info("GLL", json.encode(gll, "11g"))
end
-- 实例数据
-- {
--     "status":"A",        // 定位状态, A有效, B无效
--     "mode":"A",          // 定位模式, V无效, A单点解, D差分解
--     "sec":20,            // 秒, UTC时间为准
--     "min":23,            // 分钟, UTC时间为准
--     "hour":7,            // 小时, UTC时间为准
--     "longitude":113.231, // 经度, 正数为东经, 负数为西经
--     "latitude":23.4067,  // 纬度, 正数为北纬, 负数为南纬
--     "us":0               // 微妙数, 通常为0
-- }
]]
function gnss.getGll(data_mode)
    return  libgnss.getGll(data_mode)
end

--获取位置字符串
--[[
获取位置字符串
@api gnss.locStr(mode)
@int 字符串模式. 0- "DDMM.MMM,N,DDMMM.MM,E,1.0",1 - DDDDDDD格式
@return 指定模式的字符串
@usage
-- 仅推荐在定位成功后调用
log.info("nmea", "locStr0", json.encode(gnss.locStr(0)))
log.info("nmea", "locStr1", json.encode(gnss.locStr(1)))
-- 实例数据
locStr0	"3434.801,N,11350.40,E,1.0"
locStr1	"343480057,1135040025"
]]
function gnss.locStr(mode)
    return libgnss.locStr(mode)
end


return gnss