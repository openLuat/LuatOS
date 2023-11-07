

PROJECT = "onenetcoap"
VERSION = "1.0.0"

_G.sys = require("sys")
require "sysplus"

-- onenet的coap接入地址
udp_host = "183.230.102.122"
udp_port = 5683
-- 设备信息
produt_id = "SJaLt5cVL2"
device_name = "luatospc"
device_key = "dUZVVWRIcjVsV2pSbTJsckd0TmgyRXNnMTJWMXhIMkk="

_, _, main_token = iotauth.onenet(produt_id,device_name,device_key,"sha1")

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
                -- 这里非常重要, 获取其他请求所需要的token值
                post_token = resp.payload
            end
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
        local data = ercoap.onenet("login", produt_id, device_name, main_token)
        -- log.info("上行登陆包", data:toHex())
        socket.tx(sc, data)
    else
        log.info("udp", "其他事件", event)
    end
end

sys.taskInit(function()
    sys.waitUntil("IP_READY")
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
            -- onenet_coap_auth(string.format("$sys/%s/%s/keep_alive", produt_id, device_name))
            local data = ercoap.onenet("keep_alive", produt_id, device_name, main_token)
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
            local data = ercoap.onenet("thing/property/post", produt_id, device_name, post_token, jdata)
            -- log.info("onenet", "上行物模型数据", data:toHex())
            socket.tx(netc, data)
        end
    else
        log.info("UDP初始化失败")
        sys.wait(100)
    end
   
    log.info("连接中断, 关闭资源")
    socket.close(netc)
    socket.release(netc)
    log.info("全部结束")
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
