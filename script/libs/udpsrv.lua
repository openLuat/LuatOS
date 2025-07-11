--[[
@module udpsrv
@summary UDP服务器
@version 1.0
@date    2023.7.28
@author  wendal
@demo    socket
@tag LUAT_USE_NETWORK
@usage
-- 具体用法请查
阅demo
]]

local sys = require "sys"

local udpsrv = {}
local srvs = {}

--[[
创建UDP服务器
@api udpsrv.create(port, topic, adapter)
@int 端口号, 必填, 必须大于0小于65525
@string 收取UDP数据的topic,必填
@int 网络适配编号, 默认为nil,可选
@return table UDP服务的实体, 若创建失败会返回nil
]]
function udpsrv.create(port, topic, adapter)
    local srv = {}
    -- udpsrv.port = port
    -- srv.topic = topic
    srv.rxbuff = zbuff.create(1500)
    local sc = socket.create(adapter, function(sc, event)
        -- log.info("udpsrv", sc, event, "EVENT", socket.EVENT, "CLOSED", socket.CLOSED)
        if event == socket.EVENT then
            local rxbuff = srv.rxbuff
            while 1 do
                local succ, data_len, remote_ip, remote_port = socket.rx(sc, rxbuff)
                -- log.info("udpsrv", "???", succ, data_len, remote_ip, remote_port)
                if succ and data_len and data_len > 0 then
                    local resp = rxbuff:toStr(0, rxbuff:used())
                    rxbuff:del()
                    if remote_ip and #remote_ip == 5 then
                        local ip1,ip2,ip3,ip4 = remote_ip:byte(2),remote_ip:byte(3),remote_ip:byte(4),remote_ip:byte(5)
                        remote_ip = string.format("%d.%d.%d.%d", ip1, ip2, ip3, ip4)
                    else
                        remote_ip = nil
                    end
                    sys.publish(topic, resp, remote_ip, remote_port)
                else
                    if not succ then
                        socket.close(sc)
                        socket.connect(sc, "255.255.255.255", 0)
                    end
                    break
                end
            end
        elseif event == socket.CLOSED then
            log.info("dhcpsrv", "网络中断,执行关闭流程")
            socket.close(self.sc)
        end
    end)
    if sc == nil then
        return
    end
    srv.sc = sc
    -- socket.debug(sc, true)
    socket.config(sc, port, true)
    if socket.connect(sc, "255.255.255.255", 0) then
        srv.send = function(self, data, ip, port)
            if self.sc and data then
                -- log.info("why?", self.sc, data, ip, port)
                return socket.tx(self.sc, data, ip, port)
            end
        end
        srv.close = function(self)
            socket.close(self.sc)
            -- sys.wait(200)
            socket.release(self.sc)
            srvs[self.sc] = nil
            self.sc = nil
        end
        srvs[srv.sc] = true
        -- log.info("udpsrv", "监听开始")
        return srv
    end
    socket.close(sc)
    -- sys.wait(200)
    socket.release(sc)
    -- log.info("udpsrv", "监听失败")
end

sys.subscribe("IP_READY", function()
    for sc, value in pairs(srvs) do
        log.info("udpsrv", "自动重连udpsrv", sc)
        if sc then
            socket.connect(sc, "255.255.255.255", 0)
        end
    end
end)

return udpsrv
