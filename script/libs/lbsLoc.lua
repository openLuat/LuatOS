--[[
@module lbsLoc
@summary lbsLoc 发送基站定位请求
@version 1.0
@date    2022.12.16
@author  luatos
@usage
--注意:因使用了sys.wait()所有api需要在协程中使用
--用法实例
PRODUCT_KEY = "VmhtOb81EgZau6YyuuZJzwF6oUNGCbXi"
local lbsLoc = require("lbsLoc")
local function reqLbsLoc()
    lbsLoc.request(getLocCb)
end
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
    -- 获取经纬度成功
    if result == 0 then
        log.info("服务器返回的时间", time:toHex())
        log.info("定位类型,基站定位成功返回0", locType)
    end
    sys.timerStart(lbsLoc,20000)
end
reqLbsLoc()
]]

local lbsLoc = {}
local d1Name = "D1_TASKL"
--- 阻塞等待网卡的网络连接上，只能用于任务函数中
-- @string 任务标志
-- @int 超时时间，如果==0或者空，则没有超时一致等待
-- @... 其他参数和socket.linkup一致
-- @return 失败或者超时返回false 成功返回true
local function waitLink(taskName, timeout, ...)
	local is_err, result = socket.linkup(...)
	if is_err then
		return false
	end
	if not result then
		result = sys_wait(taskName, socket.LINK, timeout)
	else
		return true
	end
	if type(result) == 'table' and result[2] == 0 then
		return true
	else
		return false
	end
end

--- 阻塞等待IP或者域名连接上，如果加密连接还要等握手完成，只能用于任务函数中
-- @string 任务标志
-- @int 超时时间，如果==0或者空，则没有超时一致等待
-- @... 其他参数和socket.connect一致
-- @return 失败或者超时返回false 成功返回true
local function connect(taskName,timeout, ... )
	local is_err, result = socket.connect(...)
	if is_err then
		return false
	end
	if not result then
		result = sys_wait(taskName, socket.ON_LINE, timeout)
	else
		return true
	end
	if type(result) == 'table' and result[2] == 0 then
		return true
	else
		return false
	end
end

--- 阻塞等待数据发送完成，只能用于任务函数中
-- @string 任务标志
-- @int 超时时间，如果==0或者空，则没有超时一致等待
-- @... 其他参数和socket.tx一致
-- @return
-- @boolean 失败或者超时返回false，缓冲区满了或者成功返回true
-- @boolean 缓存区是否满了
local function tx(taskName,timeout, ...)
	local is_err, is_full, result = socket.tx(...)
	if is_err then
		return false, is_full
	end
	if is_full then
		return true, true
	end
	if not result then
		result = sys_wait(taskName, socket.TX_OK, timeout)
	else
		return true, is_full
	end
	if type(result) == 'table' and result[2] == 0 then
		return true, false
	else
		return false, is_full
	end
end

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
	log.info("未处理消息", msg[1], msg[2], msg[3], msg[4])
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
            log.info("rssi、mcc、mnc、lac、ci", rssi,mcc,mnc,lac,ci)
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
    local ret,cnt,k,v = "",0
    if tWifi then
        for k,v in pairs(tWifi) do
            log.info("lbsLoc.enWifiInfo",k,v)
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
    while mobile.status() == 0 do
        if not sys.waitUntil("IP_READY", timeout) then return cbFnc(1) end
    end
    local retryCnt  = 0
    sys.wait(3000)
    local reqStr = pack.pack("bAbAAAAA", productKey:len(), productKey,
                             (reqAddr and 2 or 0) + (reqTime and 4 or 0) + 8 +(reqWifi and 16 or 0) + 32, "",
                             numToBcdNum(mobile.imei()), enMuid(),
                             enCellInfo(mobile.getCellInfo()),
                             enWifiInfo(reqWifi))
    log.info("reqStr", reqStr:toHex())
    local rx_buff = zbuff.create(17)
    -- sys.wait(5000)
    while true do
        netc = socket.create(nil, d1Name) -- 创建socket对象
        if not netc then cbFnc(6) return end -- 创建socket失败
        socket.debug(netc, false)
        socket.config(netc, nil, true, nil)
        waitLink(d1Name, 0, netc)
        local result = connect(d1Name, 15000, netc, host, port)
        if result then
            while true do
                log.info(" lbsloc socket_service connect true")
                sys.wait(2000);
                local result, _ = tx(d1Name, 0, netc, reqStr) ---发送数据
                if result then
                    sys.wait(5000);
                    local is_err, param, _, _ = socket.rx(netc, rx_buff) -- 接收数据
                    log.info("是否接收和数据长度", not is_err, param)
                    if not is_err then -- 如果接收成功
                        socket.close(netc) -- 关闭连接
                        socket.release(netc)
                        local read_buff = rx_buff:toStr(0, param)
                        rx_buff:clear()
                        log.info("lbsLoc receive", read_buff:toHex())
                        if read_buff:len() >= 11 and(read_buff:byte(1) == 0 or read_buff:byte(1) == 0xFF) then
                            local locType = read_buff:byte(1)
                            cbFnc(0, trans(bcdNumToNum(read_buff:sub(2, 6))),
                                trans(bcdNumToNum(read_buff:sub(7, 11))), reqAddr and
                                read_buff:sub(13, 12 + read_buff:byte(12)) or nil,
                                read_buff:sub(reqAddr and (13 + read_buff:byte(12)) or 12, -1),
                                locType)
                        else
                            log.warn("lbsLoc.query", "根据基站查询经纬度失败")
                            if read_buff:byte(1) == 2 then
                                log.warn("lbsLoc.query","main.lua中的PRODUCT_KEY和此设备在iot.openluat.com中所属项目的ProductKey必须一致，请去检查")
                            else
                                log.warn("lbsLoc.query","基站数据库查询不到所有小区的位置信息")
                                log.warn("lbsLoc.query","在trace中向上搜索encellinfo，然后在电脑浏览器中打开http://bs.openluat.com/，手动查找encellinfo后的所有小区位置")
                                log.warn("lbsLoc.query","如果手动可以查到位置，则服务器存在BUG，直接向技术人员反映问题")
                                log.warn("lbsLoc.query","如果手动无法查到位置，则基站数据库还没有收录当前设备的小区位置信息，向技术人员反馈，我们会尽快收录")
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
发送基站/WIFI定位请求（仅支持中国区域的位置查询）
@api lbsLoc.request(cbFnc,reqAddr,timeout,productKey,host,port,reqTime,reqWifi)
@function cbFnc 用户回调函数，回调函数的调用形式为：cbFnc(result,lat,lng,addr,time,locType)
@bool reqAddr 是否请求服务器返回具体的位置字符串信息，目前此功能不完善，参数可以传nil
@number timeout 请求超时时间，单位毫秒，默认20000毫秒
@string productKey IOT网站上的产品证书，如果在main.lua中定义了PRODUCT_KEY变量，则此参数可以传nil
@string host 服务器域名，此参数可选，目前仅lib中agps.lua使用此参数。应用脚本可以直接传nil
@string port 服务器端口，此参数可选，目前仅lib中agps.lua使用此参数。应用脚本可以直接传nil
@bool reqTime 是否需要服务器返回时间信息，true返回，false或者nil不返回，此参数可选，目前仅lib中agps.lua使用此参数。应用脚本可以直接传nil
@table reqWifi 搜索到的WIFI热点信息(MAC地址和信号强度)，如果传入了此参数，后台会查询WIFI热点对应的经纬度，此参数格式如下：
{["1a:fe:34:9e:a1:77"] = -63,["8c:be:be:2d:cd:e9"] = -81,["20:4e:7f:82:c2:c4"] = -70,}
@return nil
]]
function lbsLoc.request(cbFnc,reqAddr,timeout,productKey,host,port,reqTime,reqWifi)
    sysplus.taskInitEx(taskClient, d1Name, netCB, cbFnc,reqAddr or nil,timeout or 20000,productKey or _G.PRODUCT_KEY,host or "bs.openluat.com",port or "12411",reqTime,reqWifi)
end

return lbsLoc