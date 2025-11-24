

PROJECT = "onenetcoap"
VERSION = "1.0.0"

_G.sys = require("sys")
require "sysplus"

-- onenet的coap接入地址
udp_host = "183.230.102.122"
udp_port = 5683
-- 设备信息
product_id = "SJaLt5cVL2"
device_name = "luatospc"
device_key = "dUZVVWRIcjVsV2pSbTJsckd0TmgyRXNnMTJWMXhIMkk="

_, _, main_token = iotauth.onenet(product_id,device_name,device_key,"sha1")

-- UDP事件处理函数
local rxbuff = zbuff.create(1500)
local running = false
local post_token = ""
function udpcb(sc, event)
    -- log.info("udp", sc, string.format("%08X", event))
    if event == socket.EVENT then
        local ok, len, remote_ip, remote_port = socket.rx(sc, rxbuff)
        if ok then
            local data = rxbuff:query()
            rxbuff:del()
            log.info("udp", "读到数据", data:toHex())
            ercoap.print(data)
            local resp = ercoap.parse(data)
            if resp and resp.code == 201 then
                log.info("login success", resp.code, resp.payload:toHex())
                post_token = resp.payload
            end
            -- local coapdata = libcoap.parse(data)
            -- log.info("coapdata", coapdata:code(), coapdata:type(), coapdata:hcode(), coapdata:data():toHex())
        else
            log.info("udp", "服务器断开了连接")
            running = false
            sys.publish("UDP_OFFLINE")
        end
    elseif event == socket.TX_OK then
        log.info("udp", "上行完成")
    elseif event == socket.ON_LINE then
        log.info("udp", "UDP已准备就绪,可以上行")
        -- 上行登陆包
        log.info("登陆参数", product_id, device_name, main_token)
        local data = ercoap.onenet("login", product_id, device_name, main_token)
        log.info("上行登陆包", data:toHex())
        socket.tx(sc, data)
    else
        log.info("udp", "其他事件", event)
    end
end

sys.taskInit(function()
    sys.wait(100)
    log.info("创建 udp netc")
    local netc = socket.create(nil, udpcb)
    -- log.info("netc", netc)
    socket.config(netc, nil, true)
    -- socket.debug(netc, true)
    log.info("执行连接")
    local ok = socket.connect(netc, udp_host, udp_port)
    log.info("socket connect", ok)
    if ok then
        running = true
        while running do
            local result = sys.waitUntil("UDP_OFFLINE", 30000)
            if result then
               break
            end
            -- 上行心跳包
            -- onenet_coap_auth(string.format("$sys/%s/%s/keep_alive", product_id, device_name))
            local data = ercoap.onenet("keep_alive", product_id, device_name, main_token)
            -- log.info("上行心跳包", data:toHex())
            socket.tx(netc, data)

            sys.wait(1000)
            local post = {
                id = "123",
                -- st = token,
                params = {
                    -- WaterConsumption = {
                    --     value = 1.5
                    -- },
                    WaterMeterState = {
                        value = 0
                    }
                }
            }
            local jdata = (json.encode(post, "2f"))
            log.info("uplink", jdata)
            -- jdata = [[{"id":"3","version":"1.0","params":{"WaterMeterState":{"value":0}}}]]
            -- log.info("uplink2", jdata)
            log.info("uplink", "thing/property/post", product_id, device_name, post_token:toHex(), jdata)
            local data = ercoap.onenet("thing/property/post", product_id, device_name, post_token, jdata)
            -- log.info("onenet", "上行物模型数据", data:toHex())
            socket.tx(netc, data)
        end
    else
        log.info("UDP初始化失败")
        sys.wait(100)
    end

    -- socket.tx(netc, "ABC", "112.125.89.8", 45022)
    -- socket.tx(netc, "ABC1234567890")

   
    log.info("连接中断, 关闭资源")
    socket.close(netc)
    socket.release(netc)
    log.info("全部结束")
end)

sys.run()

--[[
48020004B9E300448CC2B651B4247379730A534A614C743563564C32086C7561746F737063057468696E670870726F706572747904706F737411325132FF7B226964223A2233222C2276657273696F6E223A22312E30222C22706172616D73223A7B2257617465724D657465725374617465223A7B2276616C7565223A307D7D7D
4802000376657273696F6E3DB4247379730A534A614C743563564C32086C7561746F737063057468696E670870726F706572747904706F737411325132FF7B226964223A2233222C2276657273696F6E223A22312E30222C22706172616D73223A7B2257617465724D657465725374617465223A7B2276616C7565223A307D7D7D
440200031B076901B4247379730A534A614C743563564C32086C7561746F737063057468696E670870726F706572747904706F737411325132FF7B226964223A2233222C2276657273696F6E223A22312E30222C22706172616D73223A7B2257617465724D657465725374617465223A7B2276616C7565223A307D7D7D
]]