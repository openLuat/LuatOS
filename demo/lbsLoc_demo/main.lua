-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "mobiledemo"
VERSION = "1.0.0"

local PRODUCT_KEY = "VmhtOb81EgZau6YyuuZJzwF6oUNGCbXi"

log.info("main", PROJECT, VERSION)

-- sys库是标配
_G.sys = require("sys")
_G.sysplus = require("sysplus")

local d1Name = "D1_TASK"
local libnet = require "libnet"
local common =require "common"
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
        --log.info("ret",json.encode(ret))
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

local function trans(str)  --如果字符串<10,则用0补到10位
    local s = str
    if str:len()<10 then
        s = str..string.rep("0",10-str:len())
    end

    return s:sub(1,3).."."..s:sub(4,10)
end

-----------------------------------------------------------------------------------------------------------------------------------------------------
local function taskClient(cbFnc, reqAddr, timeout, productKey, host, port,reqTime, reqWifi)
    while not mobile.status() do
        if not sys.waitUntil("IP_READY", timeout) then return cbFnc(1) end
    end
    sys.wait(3000)
    local reqStr = pack.pack("bAbAAAA", productKey:len(), productKey,
                             (reqAddr and 2 or 0) + (reqTime and 4 or 0) + 8 +(reqWifi and 16 or 0) + 32, 
                             "",
                             common.numToBcdNum(mobile.imei()), 
                             enMuid(),
                             enCellInfo(mobile.getCellInfo()))
    log.info("reqStr", reqStr:toHex())
    local rx_buff = zbuff.create(17)
    while true do
        sys.wait(5000)
        netc = socket.create(nil, d1Name) -- 创建socket对象
        if netc then
            log.info("创建socket对象成功")
            socket.debug(netc, true)
            socket.config(netc, nil, true, nil)
            libnet.waitLink(d1Name, 0, netc)
            local result = libnet.connect(d1Name, 15000, netc, host, port)
            if result then
                while true do
                    sys.wait(20000);
                    log.info("socket connect true")
                    local result, isfull = libnet.tx(d1Name, 0, netc, reqStr) ---发送数据
                    if result then
                        sys.wait(10000);
                        local is_err, param, _, _ = socket.rx(netc, rx_buff) -- 接收数据
                        log.info("是否接收和数据长度", is_err, param)
                        if not is_err and (param > 0) then -- 如果接收成功
                            -- socket.close(netc)    --关闭连接
                            local read_buff = rx_buff:toStr(0, param)
                            log.info("lbsLoc receive", read_buff:toHex())
                            if read_buff:len() >= 11 and(read_buff:byte(1) == 0 or read_buff:byte(1) ==0xFF) then
                                local locType = read_buff:byte(1)
                                cbFnc(0, trans(common.bcdNumToNum(read_buff:sub(2, 6))),
                                    trans(common.bcdNumToNum(read_buff:sub(7, 11))),
                                    reqAddr and read_buff:sub(13,12 + read_buff:byte(12)) or nil, 
                                    read_buff:sub(reqAddr and (13 + read_buff:byte(12)) or 12, -1), 
                                    locType)

                            else
                                log.warn("lbsLoc.query","根据基站查询经纬度失败")
                                if read_buff:byte(1) == 2 then
                                    log.warn("lbsLoc.query", "main.lua中的PRODUCT_KEY和此设备在iot.openluat.com中所属项目的ProductKey必须一致，请去检查")
                                else
                                    log.warn("lbsLoc.query","基站数据库查询不到所有小区的位置信息")
                                    log.warn("lbsLoc.query","在trace中向上搜索encellinfo，然后在电脑浏览器中打开http://bs.openluat.com/，手动查找encellinfo后的所有小区位置")
                                    log.warn("lbsLoc.query", "如果手动可以查到位置，则服务器存在BUG，直接向技术人员反映问题")
                                    log.warn("lbsLoc.query","如果手动无法查到位置，则基站数据库还没有收录当前设备的小区位置信息，向技术人员反馈，我们会尽快收录")
                                end
                                cbFnc(5)
                            end

                        else
                            socket.close(netc)
                            cbFnc(4)
                            break
                        end
                    else
                        socket.close(netc)
                        cbFnc(3) -- 发送数据失败
                        break
                    end
                end
            else
                socket.close(netc)
            end
        end
    end

end


local function cbFnc(result, lat, lng, addr, time, locType)
    log.info("testLbsLoc.getLocCb", result, lat, lng)
    -- 获取经纬度成功
    if result == 0 then
        log.info("服务器返回的时间", time:toHex())
        log.info("定位类型，基站定位成功返回0", locType)
        -- 失败
    end

end



-- sys.taskInit(taskClient,cbFnc,nil,20000, PRODUCT_KEY,"112.125.89.8","37975",nil,nil)


sysplus.taskInitEx(taskClient, d1Name, netCB, cbFnc,nil,20000, PRODUCT_KEY,"bs.openluat.com",12411,nil,nil)
--sysplus.taskInitEx(taskClient, d1Name, netCB, cbFnc,nil,20000, PRODUCT_KEY,"112.125.89.8",33560,nil,nil)







-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
