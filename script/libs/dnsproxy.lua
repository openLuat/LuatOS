--[[
@module dnsproxy
@summary DNS代理转发
@version 1.0
@date    2024.4.20
@author  wendal
@demo    socket
@tag LUAT_USE_NETWORK
@usage
-- 具体用法请查阅demo
]]

local sys = require "sys"

local dnsproxy = {}
dnsproxy.map = {}
dnsproxy.txid = 0x1234
dnsproxy.rxbuff = zbuff.create(1500)

function dnsproxy.on_request(sc, event)
    if event == socket.EVENT then
        local rxbuff = dnsproxy.rxbuff
        while 1 do
            rxbuff:seek(0)
            local succ, data_len, remote_ip, remote_port = socket.rx(sc, rxbuff)
            if succ and data_len and data_len > 0 then
                if remote_ip and #remote_ip == 5 then
                    local ip1,ip2,ip3,ip4 = remote_ip:byte(2),remote_ip:byte(3),remote_ip:byte(4),remote_ip:byte(5)
                    remote_ip = string.format("%d.%d.%d.%d", ip1, ip2, ip3, ip4)
                    local txid_request = rxbuff[0] + rxbuff[1] * 256
                    local txid_map = dnsproxy.txid
                    dnsproxy.txid = dnsproxy.txid + 1
                    table.insert(dnsproxy.map, {txid_request, txid_map, remote_ip, remote_port})
                    rxbuff[0] = txid_map % 256
                    rxbuff[1] = txid_map // 256
                    socket.tx(dnsproxy.main_sc, rxbuff, "114.114.114.114", 53)
                end
            else
                break
            end
        end
    end
end

function dnsproxy.on_response(sc, event)
    if event == socket.EVENT then
        local rxbuff = dnsproxy.rxbuff
        while 1 do
            rxbuff:seek(0)
            local succ, data_len = socket.rx(sc, rxbuff)
            if succ and data_len and data_len > 0 then
                if true then
                    -- local ip1,ip2,ip3,ip4 = remote_ip:byte(2),remote_ip:byte(3),remote_ip:byte(4),remote_ip:byte(5)
                    -- remote_ip = string.format("%d.%d.%d.%d", ip1, ip2, ip3, ip4)
                    local txid_resp = rxbuff[0] + rxbuff[1] * 256
                    local index = -1
                    for i, mapit in pairs(dnsproxy.map) do
                        if mapit[2] == txid_resp then
                            local txid_request = mapit[1]
                            local remote_ip = mapit[3]
                            local remote_port = mapit[4]
                            rxbuff[0] = txid_request % 256
                            rxbuff[1] = txid_request // 256
                            socket.tx(dnsproxy.sc, rxbuff, remote_ip, remote_port)
                            index = i
                            break
                        end
                    end
                    if index > 0 then
                        table.remove(dnsproxy.map, index)
                    end
                end
            else
                break
            end
        end
    end
end

--[[
创建UDP服务器
@api dnsproxy.create(port, topic, adapter)
@int 端口号, 必填, 必须大于0小于65525
@string 收取UDP数据的topic,必填
@int 网络适配编号, 默认为nil,可选
@return table UDP服务的实体, 若创建失败会返回nil
]]
function dnsproxy.setup(adapter, main_adapter)
    log.info("dnsproxy", adapter, main_adapter)
    dnsproxy.sc = socket.create(adapter, dnsproxy.on_request)
    dnsproxy.main_sc = socket.create(main_adapter, dnsproxy.on_response)
    socket.config(dnsproxy.sc, 53, true)
    socket.config(dnsproxy.main_sc, nil, true)
    socket.connect(dnsproxy.sc, "255.255.255.255", 0)
    socket.connect(dnsproxy.main_sc, "114.114.114.114", 53)
    return true
end

return dnsproxy
