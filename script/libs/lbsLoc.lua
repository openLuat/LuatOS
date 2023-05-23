--[[
@module lbsLoc
@summary lbsLoc 发送基站定位请求
@version 1.0
@date    2022.12.16
@author  luatos
@usage
--注意:因使用了sys.wait()所有api需要在协程中使用
--用法实例
--注意：此处的PRODUCT_KEY仅供演示使用，不保证一直能用，量产项目中一定要使用自己在iot.openluat.com中创建的项目productKey
PRODUCT_KEY = "v32xEAKsGTIEQxtqgwCldp5aPlcnPs3K"
local lbsLoc = require("lbsLoc")
-- 功能:获取基站对应的经纬度后的回调函数
-- 参数:-- result：number类型，0表示成功，1表示网络环境尚未就绪，2表示连接服务器失败，3表示发送数据失败，4表示接收服务器应答超时，5表示服务器返回查询失败；为0时，后面的5个参数才有意义
		-- lat：string类型，纬度，整数部分3位，小数部分7位，例如031.2425864
		-- lng：string类型，经度，整数部分3位，小数部分7位，例如121.4736522
        -- addr：目前无意义
        -- time：string类型或者nil，服务器返回的时间，6个字节，年月日时分秒，需要转为十六进制读取
            -- 第一个字节：年减去2000，例如2017年，则为0x11
            -- 第二个字节：月，例如7月则为0x07，12月则为0x0C
            -- 第三个字节：日，例如11日则为0x0B
            -- 第四个字节：时，例如18时则为0x12
            -- 第五个字节：分，例如59分则为0x3B
            -- 第六个字节：秒，例如48秒则为0x30
        -- locType：numble类型或者nil，定位类型，0表示基站定位成功，255表示WIFI定位成功
function getLocCb(result, lat, lng, addr, time, locType)
    log.info("testLbsLoc.getLocCb", result, lat, lng)
    -- 获取经纬度成功, 坐标系WGS84
    if result == 0 then
        log.info("服务器返回的时间", time:toHex())
        log.info("定位类型,基站定位成功返回0", locType)
    end
end
lbsLoc.request(getLocCb)
]]

local sys = require "sys"
local sysplus = require("sysplus")
local libnet = require("libnet")

local lbsLoc = {}
local d1Name = "lbsLoc"

--- ASCII字符串 转化为 BCD编码格式字符串(仅支持数字)
-- @string inStr 待转换字符串
-- @number destLen 转换后的字符串期望长度，如果实际不足，则填充F
-- @return string data,转换后的字符串
-- @usage
local function numToBcdNum(inStr,destLen)
    local l,t,num = string.len(inStr or ""),{}
    destLen = destLen or (inStr:len()+1)/2
    for i=1,l,2 do
        num = tonumber(inStr:sub(i,i+1),16)
        if i==l then
            num = 0xf0+num
        else
            num = (num%0x10)*0x10 + (num-(num%0x10))/0x10
        end
        table.insert(t,num)
    end

    local s = string.char(unpack(t))

    l = string.len(s)
    if l < destLen then
        s = s .. string.rep("\255",destLen-l)
    elseif l > destLen then
        s = string.sub(s,1,destLen)
    end

    return s
end

--- BCD编码格式字符串 转化为 号码ASCII字符串(仅支持数字)
-- @string num 待转换字符串
-- @return string data,转换后的字符串
-- @usage
local function bcdNumToNum(num)
	local byte,v1,v2
	local t = {}

	for i=1,num:len() do
		byte = num:byte(i)
		v1,v2 = bit.band(byte,0x0f),bit.band(bit.rshift(byte,4),0x0f)

		if v1 == 0x0f then break end
		table.insert(t,v1)

		if v2 == 0x0f then break end
		table.insert(t,v2)
	end

	return table.concat(t)
end


local function netCB(msg)
	--log.info("未处理消息", msg[1], msg[2], msg[3], msg[4])
end


local function enCellInfo(s)
    local ret,t,mcc,mnc,lac,ci,rssi,k,v,m,n,cntrssi = "",{}
        for k,v in pairs(s) do
            mcc,mnc,lac,ci,rssi = v.mcc,v.mnc,v.tac,v.cid,((v.rsrq + 144) >31) and 31 or (v.rsrq + 144)
            local handle = nil
            for k,v in pairs(t) do
                if v.lac == lac and v.mcc == mcc and v.mnc == mnc then
                    if #v.rssici < 8 then
                        table.insert(v.rssici,{rssi=rssi,ci=ci})
                    end
                    handle = true
                break
                end
            end
            if not handle then
                table.insert(t,{mcc=mcc,mnc=mnc,lac=lac,rssici={{rssi=rssi,ci=ci}}})
            end
            log.debug("rssi,mcc,mnc,lac,ci", rssi,mcc,mnc,lac,ci)
        end
        for k,v in pairs(t) do
            ret = ret .. pack.pack(">HHb",v.lac,v.mcc,v.mnc)
            for m,n in pairs(v.rssici) do
                cntrssi = bit.bor(bit.lshift(((m == 1) and (#v.rssici-1) or 0),5),n.rssi)
                ret = ret .. pack.pack(">bi",cntrssi,n.ci)
            end
        end
        return string.char(#t)..ret
end

local function enWifiInfo(tWifi)
    local ret,cnt = "", 0
    if tWifi then
        for k,v in pairs(tWifi) do
            -- log.info("lbsLoc.enWifiInfo",k,v)
            ret = ret..pack.pack("Ab",(k:gsub(":","")):fromHex(),(v<0) and (v+255) or v)
            cnt = cnt+1
        end
    end
    return string.char(cnt)..ret
end

local function enMuid()   --获取模块MUID
    local muid = mobile.muid()
    return string.char(muid:len())..muid
end

local function trans(str)
    local s = str
    if str:len()<10 then
        s = str..string.rep("0",10-str:len())
    end

    return s:sub(1,3).."."..s:sub(4,10)
end


local function taskClient(cbFnc, reqAddr, timeout, productKey, host, port,reqTime, reqWifi)
    if mobile.status() == 0 then
        if not sys.waitUntil("IP_READY", timeout) then return cbFnc(1) end
        sys.wait(500)
    end
    if productKey == nil then
        productKey = ""
    end
    local retryCnt  = 0
    local reqStr = pack.pack("bAbAAAAA", productKey:len(), productKey,
                             (reqAddr and 2 or 0) + (reqTime and 4 or 0) + 8 +(reqWifi and 16 or 0) + 32, "",
                             numToBcdNum(mobile.imei()), enMuid(),
                             enCellInfo(mobile.getCellInfo()),
                             enWifiInfo(reqWifi))
    log.debug("reqStr", reqStr:toHex())
    local rx_buff = zbuff.create(17)
    -- sys.wait(5000)
    while true do
        local result,succ,param
        local netc = socket.create(nil, d1Name) -- 创建socket对象
        if not netc then cbFnc(6) return end -- 创建socket失败
        socket.debug(netc, false)
        socket.config(netc, nil, true, nil)
        result = libnet.waitLink(d1Name, 0, netc)
        result = libnet.connect(d1Name, 5000, netc, host, port)
        if result then
            while true do
                -- log.info(" lbsloc socket_service connect true")
                result = libnet.tx(d1Name, 0, netc, reqStr) ---发送数据
                if result then
                    result, param = libnet.wait(d1Name, 15000 + retryCnt * 5, netc)
                    if not result then
                        socket.close(netc)
                        socket.release(netc)
                        retryCnt = retryCnt+1
                        if retryCnt>=3 then return cbFnc(4) end
                        break
                    end
                    succ, param = socket.rx(netc, rx_buff) -- 接收数据
                    -- log.info("是否接收和数据长度", succ, param)
                    if param ~= 0 then -- 如果接收成功
                        socket.close(netc) -- 关闭连接
                        socket.release(netc)
                        local read_buff = rx_buff:toStr(0, param)
                        rx_buff:clear()
                        log.debug("lbsLoc receive", read_buff:toHex())
                        if read_buff:len() >= 11 and(read_buff:byte(1) == 0 or read_buff:byte(1) == 0xFF) then
                            local locType = read_buff:byte(1)
                            cbFnc(0, trans(bcdNumToNum(read_buff:sub(2, 6))),
                                trans(bcdNumToNum(read_buff:sub(7, 11))), reqAddr and
                                read_buff:sub(13, 12 + read_buff:byte(12)) or nil,
                                reqTime and read_buff:sub(reqAddr and (13 + read_buff:byte(12)) or 12, -1) or "",
                                locType)
                        else
                            log.warn("lbsLoc.query", "根据基站查询经纬度失败")
                            if read_buff:byte(1) == 2 then
                                log.warn("lbsLoc.query","main.lua中的PRODUCT_KEY和此设备在iot.openluat.com中所属项目的ProductKey必须一致，请去检查")
                            else
                                log.warn("lbsLoc.query","基站数据库查询不到所有小区的位置信息")
                                -- log.warn("lbsLoc.query","在trace中向上搜索encellinfo，然后在电脑浏览器中打开http://bs.openluat.com/，手动查找encellinfo后的所有小区位置")
                                -- log.warn("lbsLoc.query","如果手动可以查到位置，则服务器存在BUG，直接向技术人员反映问题")
                                -- log.warn("lbsLoc.query","如果手动无法查到位置，则基站数据库还没有收录当前设备的小区位置信息，向技术人员反馈，我们会尽快收录")
                            end
                            cbFnc(5)
                        end
                        return
                    else
                        socket.close(netc)
                        socket.release(netc)
                        retryCnt = retryCnt+1
                        if retryCnt>=3 then return cbFnc(4) end
                        break
                    end
                else
                    socket.close(netc)
                    socket.release(netc)
                    retryCnt = retryCnt+1
                    if retryCnt>=3 then return cbFnc(3) end
                    break
                end
            end
        else
            socket.close(netc)
            socket.release(netc)
            retryCnt = retryCnt + 1
            if retryCnt >= 3 then return cbFnc(2) end
        end
    end
end


--[[
发送基站定位请求
@api lbsLoc.request(cbFnc,reqAddr,timeout,productKey,host,port,reqTime,reqWifi)
@function cbFnc 用户回调函数，回调函数的调用形式为：cbFnc(result,lat,lng,addr,time,locType)
@bool reqAddr 是否请求服务器返回具体的位置字符串信息，已经不支持,填false或者nil
@number timeout 请求超时时间，单位毫秒，默认20000毫秒
@string productKey IOT网站上的产品KEY，如果在main.lua中定义了PRODUCT_KEY变量，则此参数可以传nil
@string host 服务器域名, 默认 "bs.openluat.com" ,可选备用服务器(不保证可用) "bs.air32.cn"
@string port 服务器端口，默认"12411",一般不需要设置
@return nil
@usage
-- 提醒: 返回的坐标值, 是WGS84坐标系
]]
function lbsLoc.request(cbFnc,reqAddr,timeout,productKey,host,port,reqTime,reqWifi)
    sysplus.taskInitEx(taskClient, d1Name, netCB, cbFnc, reqAddr,timeout or 20000,productKey or _G.PRODUCT_KEY,host or "bs.openluat.com",port or "12411", reqTime == nil and true or reqTime)
end

return lbsLoc