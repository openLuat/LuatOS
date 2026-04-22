--[[
@module airlbs
@summary airlbs 定位服务(收费服务，需自行联系销售申请)
@version 1.0
@date    2024.11.01
@author  Dozingfiretruck
@usage
-- lbsloc 是异步回调接口，
-- lbsloc2 是是同步接口。
-- lbsloc比lbsloc2多了一个请求地址文本的功能。
-- lbsloc 和 lbsloc2 都是免费LBS定位的实现方式；
-- airlbs 扩展库是收费 LBS 的实现方式。
]] 


libnet = require "libnet"

local airlbs_host = "airlbs.openluat.com"
local airlbs_port = 12413

local lib_name = "airlbs"
local lib_topic = lib_name .. "topic"

local location_data = 0
local disconnect = -1
local airlbs_timeout = 15000
local bsp = rtos.bsp()
local airlbs = {}

local function airlbs_task(task_name, buff, timeout, adapter)
    local netc = socket.create(nil, lib_name)
    socket.config(netc, adapter, true) -- udp

    sysplus.cleanMsg(lib_name)
    local result = libnet.connect(lib_name, 15000, netc, airlbs_host, airlbs_port)
    if result then
        log.info(lib_name, "服务器连上了")
        libnet.tx(lib_name, 0, netc, buff)
    else
        log.info(lib_name, "服务器没连上了!!!")
        sys.publish(lib_topic, disconnect)
        libnet.close(lib_name, 5000, netc)
        return
    end
    buff:del()
    while result do
        local succ, param = socket.rx(netc, buff)
        if not succ then
            log.error(lib_name, "服务器断开了", succ, param)
            sys.publish(lib_topic, disconnect)
            break
        end
        if buff:used() > 0 then
            local location = nil
            local data = buff:query(0, 1) -- 获取数据
            if data:toHex() == '00' then
                location = json.decode(buff:query(1))
            else
                log.error(lib_name, "not json data")
            end
            sys.publish(lib_topic, location_data, location)
            buff:del()
            break
        end
        result, param, param2 = libnet.wait(lib_name, timeout, netc)
        log.info(lib_name, "wait", result, param, param2)
        if param == false then
            log.error(lib_name, "服务器断开了", succ, param)
            sys.publish(lib_topic, disconnect)
            break
        end
    end
    libnet.close(lib_name, 5000, netc)
end

-- 处理未识别的网络消息
local function netCB(msg)
    log.info("未处理消息", msg[1], msg[2], msg[3], msg[4])
end

--[[
获取定位数据
@api airlbs.request(param)
@param table 参数(联系销售获取id与key) project_id:项目ID project_key:项目密钥 timeout:超时时间,单位毫秒 默认15000 adapter: 网络适配器id,可选,默认是平台自带的网络协议栈
@return bool 成功返回true,失败会返回false
@return table 定位成功生效，成功返回定位数据
@usage
--注意:函数内因使用了sys.waitUntil阻塞接口，所以api需要在协程中使用
--注意:使用前需同步时间

local airlbs = require "airlbs"

sys.taskInit(function()
    -- 等待网络就绪
    sys.waitUntil("IP_READY")
    -- 执行时间同步
    socket.sntp()
    sys.waitUntil("NTP_UPDATE", 10000)
    while 1 do
        -- airlbs请求定位
        local result ,data = airlbs.request({
            project_id = airlbs_project_id,
            project_key = airlbs_project_key,
            timeout = 10000, 
            adapter = socket.LWIP_STA
            })
        if result then
            log.info("airlbs", json.encode(data))
        end
        sys.wait(20000)
    end
end)
]]
function airlbs.request(param)
    if not param or param.project_id == nil or param.project_key == nil then
        log.error(lib_name, "param error")
        return false
    end

    if not mobile and not param.wifi_info then
        log.error(lib_name, "no mobile and no wifi_info")
        return false
    end

    local udp_buff = zbuff.create(1500)
    local auth_type = 0x01
    local lbs_data_type = 0x00
    local project_id = param.project_id
    if project_id:len() ~= 6 then
        log.error("airlbs", "project_id len not 6")
    end
    local timestamp = os.time()
    local project_key = param.project_key
    local nonce = crypto.trng(6)
    local hmac_data
    local muid
    local mac1 = netdrv.mac(socket.LWIP_STA)
    local mac
    log.info("mac", mac)
    log.info("硬件型号", rtos.bsp())
    if bsp == "Air8101" then
        muid =  mcu.muid() or ""
        if muid ~= "" then
            mac = "MAC" .. mac1 
        else
            mac = "M01" .. mac1 
            muid = crypto.sha256(mac):sub(1,32)
        end
        log.info("muid", muid,mac)
        hmac_data = crypto.hmac_sha1(project_id .. mac .. muid .. timestamp .. nonce, project_key)
    else
        local imei = mobile and mobile.imei() or ""
        muid = mobile and mobile.muid() or ""
        hmac_data = crypto.hmac_sha1(project_id .. imei .. muid .. timestamp .. nonce, project_key)
    end
    -- log.debug(lib_name,"hmac_sha1", hmac_data)
    local lbs_data = {}
    if mobile then
        mobile.reqCellInfo(60)
        sys.waitUntil("CELL_INFO_UPDATE", param.timeout or airlbs_timeout)
        lbs_data.cells = {}
        -- log.info("cell", json.encode(mobile.getCellInfo()))
        for k, v in pairs(mobile.getCellInfo()) do
            lbs_data.cells[k] = {}
            lbs_data.cells[k][1] = v.mcc
            lbs_data.cells[k][2] = v.mnc
            lbs_data.cells[k][3] = v.tac
            lbs_data.cells[k][4] = v.cid
            lbs_data.cells[k][5] = v.rssi or v.rsrp
            lbs_data.cells[k][6] = v.snr
            lbs_data.cells[k][7] = v.pci
            lbs_data.cells[k][8] = v.rsrp
            lbs_data.cells[k][9] = v.rsrq
            lbs_data.cells[k][10] = v.earfcn
        end
    end
    if param.wifi_info and #param.wifi_info > 0 then
        lbs_data.macs = {}
        for k, v in pairs(param.wifi_info) do
            lbs_data.macs[k] = {}
            lbs_data.macs[k][1] = v.bssid:toHex():gsub("(%x%x)", "%1:"):sub(1, -2)
            lbs_data.macs[k][2] = v.rssi
        end
    end
    local lbs_jdata = json.encode(lbs_data)
    log.info("扫描出的数据",lbs_jdata)
    if bsp == "Air8101" then
        udp_buff:write(string.char(auth_type) .. project_id .. mac .. muid ..  timestamp .. nonce .. hmac_data:fromHex() .. string.char(lbs_data_type) .. lbs_jdata)
    else
        local imei = mobile and mobile.imei() or ""
        local muid = mobile and mobile.muid() or ""
        udp_buff:write(string.char(auth_type) .. project_id .. imei .. muid .. timestamp .. nonce .. hmac_data:fromHex() .. string.char(lbs_data_type) .. lbs_jdata)
    end

    sysplus.taskInitEx(airlbs_task, lib_name, netCB, lib_name, udp_buff, param.timeout or airlbs_timeout, param.adapter)

    while 1 do
        local result, tp, data = sys.waitUntil(lib_topic, param.timeout or airlbs_timeout)
        log.info("定位请求的结果", result, "超时时间", tp, data,json.encode(data))
        if not result then
            return false, "timeout"
        elseif tp == location_data then
            if not data then
                log.error(lib_name, "无数据, 请检查project_id和project_key")
                return false
                -- data.result 0-找不到 1-成功 2-qps超限 3-欠费 4-其他错误 
            elseif data.result == 0 then
                log.error(lib_name, "no location(基站定位服务器查询当前地址失败)")
                return false
            elseif data.result == 1 then
                if bsp == "Air8101" then
                log.info("多wifi请求成功,服务器返回的原始数据", data)
                else
                log.info("多基站请求成功,服务器返回的原始数据", data)
                end
                return true, {
                    lng = data.lng,
                    lat = data.lat
                }
            elseif data.result == 2 then
                log.error(lib_name, "qps limit(当前请求已到达限制,请检查当前请求是否过于频繁))")
                return false
            elseif data.result == 3 then
                log.error(lib_name, "当前设备已欠费,请联系销售充值")
                return false
            elseif data.result == 4 then
                log.error(lib_name, "other error")
                return false
            else
                log.error("其他错误,错误码", data.result, lib_name)
            end
        else
            log.error(lib_name, "net error")
            return false
        end
    end

end

--[[
获取地址信息
@api airlbs.get_address(lat, lng, param)
@param number 纬度
@param number 经度
@param table 参数 timeout:超时时间,单位毫秒 默认10000 adapter: 网络适配器id,可选,默认是平台自带的网络协议栈
@return bool 成功返回true,失败会返回false
@return string 成功返回地址信息,失败返回错误信息
@usage
--注意:函数内因使用了http.request阻塞接口，所以api需要在协程中使用

local airlbs = require "airlbs"

sys.taskInit(function()
    -- 等待网络就绪
    sys.waitUntil("IP_READY")
    -- 获取地址信息
    local result, address = airlbs.get_address(lat, lng)
    if result then
        log.info("airlbs.get_address", address)
    else
        log.info("airlbs.get_address失败", address)
    end
end)
]]
function airlbs.get_address(lat, lng, param)
    if not lat or not lng then
        log.error(lib_name, "lat or lng is nil")
        return false, "lat or lng is nil"
    end
    
    local device_id, muid
    if bsp == "Air8101" then
        -- WIFI 设备，使用 MAC 地址
        local mac1 = netdrv.mac(socket.LWIP_STA)
        muid = mcu.muid() or ""
        if muid ~= "" then
            device_id = "MAC" .. mac1 
        else
            device_id = "M01" .. mac1 
            muid = crypto.sha256(device_id):sub(1,32)
        end
        log.info(lib_name, "Using WIFI device ID:", device_id, "muid:", muid)
    else
        -- 4G 设备，使用 IMEI
        device_id = mobile and mobile.imei() or ""
        muid = mobile and mobile.muid() or ""
        log.info(lib_name, "Using 4G device ID:", device_id)
    end
    
    local url = string.format("http://iot.openluat.com/api/open/device_get_address?imei=%s&muid=%s&lat=%f&lon=%f", 
        device_id, muid, lat, lng)
    
    local timeout = (param and param.timeout) or 10000
    local code, headers, body = http.request("GET", url, nil, nil, {timeout=timeout}).wait()
    
    if code == 200 then
        log.info(lib_name, "获取地址成功, 响应体:", body)
        local podata = json.decode(body)
        if podata.address then
            return true, podata.address
        else
            return false, "获取地址失败"
        end
    else
        log.error(lib_name, "获取地址失败, 状态码:", code, "响应体:", body)
        return false, "网络请求失败"
    end
end

return airlbs

