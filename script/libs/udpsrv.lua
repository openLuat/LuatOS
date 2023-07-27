--[[
@module udpsrv
@summary UDP服务器
@version 1.0
@date    2023.7.28
@author  wendal
@demo    socket
@usage
-- 具体用法请查阅demo
]]

local sys = require "sys"

local udpsrv = {}

--[[
创建UDP服务器
@api udpsrv.create(port, topic)
@int 端口号, 必填, 必须大于0小于65525
@string 收取UDP数据的topic
@return table UDP服务的实体, 若创建失败会返回nil
]]
function udpsrv.create(port, topic)
    local srv = {}
    -- udpsrv.port = port
    -- srv.topic = topic
    srv.rxbuff = zbuff.create(1500)
    local sc = socket.create(nil, function(sc, event)
        -- log.info("udpsrv", sc, event)
        if event == socket.EVENT then
            local rxbuff = srv.rxbuff
            local succ, data_len = socket.rx(sc, rxbuff)
            if succ and data_len and data_len > 0 then
                local resp = rxbuff:toStr(0, rxbuff:used())
                rxbuff:del()
                sys.publish(udpsrv.topic, resp)
            end
        end
    end)
    if sc == nil then
        return
    end
    srv.sc = sc
    -- socket.debug(sc, true)
    socket.config(sc, port, true)
    if socket.connect(sc, "0.0.0.0", 0) then
        srv.send = function(self, data, ip, port)
            if self.sc and data then
                -- log.info("why?", self.sc, data, ip, port)
                return socket.tx(self.sc, data, ip or "0.0.0.0", port)
            end
        end
        srv.close = function(self)
            socket.close(self.sc)
            -- sys.wait(200)
            socket.release(self.sc)
            self.sc = nil
        end
        -- log.info("udpsrv", "监听开始")
        return srv
    end
    socket.close(udpsrv.sc)
    -- sys.wait(200)
    socket.release(udpsrv.sc)
    -- log.info("udpsrv", "监听失败")
end

return udpsrv
