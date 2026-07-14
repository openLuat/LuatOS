local t = {}

local udp_limit_suite = {}

local function wait_socket_evt(topic, expected, timeout)
    local deadline = ((mcu and mcu.ticks and mcu.ticks()) or 0) + timeout
    while true do
        local now = (mcu and mcu.ticks and mcu.ticks()) or 0
        local remain = timeout
        if deadline > 0 then
            remain = deadline - now
            if remain <= 0 then
                return false
            end
        end
        local result, evt, param = sys.waitUntil(topic, remain)
        if result == false then
            return false
        end
        if evt == expected then
            return true, param
        end
    end
end

local function close_client(netc)
    if not netc then
        return
    end
    pcall(socket.close, netc)
    pcall(socket.release, netc)
end

local function create_udp_server(port, topic)
    local srv = {
        rxbuff = zbuff.create(1500)
    }
    local sc = socket.create(nil, function(sc, event)
        if event == socket.EVENT then
            while true do
                local succ, data_len, remote_ip, remote_port = socket.rx(sc, srv.rxbuff)
                if succ and data_len and data_len > 0 then
                    local resp = srv.rxbuff:toStr(0, srv.rxbuff:used())
                    srv.rxbuff:del()
                    if remote_ip and #remote_ip == 5 then
                        remote_ip = string.format("%d.%d.%d.%d",
                            remote_ip:byte(2), remote_ip:byte(3), remote_ip:byte(4), remote_ip:byte(5))
                    else
                        remote_ip = nil
                    end
                    sys.publish(topic, resp, remote_ip, remote_port)
                else
                    break
                end
            end
        end
    end)
    assert(sc, "server socket.create failed")
    srv.sc = sc
    assert(socket.config(sc, port, true), "server socket.config failed")
    assert(socket.connect(sc, "255.255.255.255", 0), "server socket.connect failed")
    function srv:send(data, ip, remote_port)
        return socket.tx(self.sc, data, ip, remote_port)
    end
    function srv:close()
        socket.close(self.sc)
        socket.release(self.sc)
        self.sc = nil
    end
    return srv
end

function udp_limit_suite.test_udp_rx_limit_discards_tail()
    local tick = (mcu and mcu.ticks and mcu.ticks()) or 0
    local port = 45000 + (tick % 1000)
    local client_port = port + 1000
    local client_topic = "udp_limit_evt_" .. tostring(tick)
    local server_topic = client_topic .. "_server"
    local payload = "ABCDEFGHIJ"
    local buff = zbuff.create(64)
    local srv = create_udp_server(port, server_topic)
    local netc = socket.create(nil, function(_, evt, param)
        sys.publish(client_topic, evt, param)
    end)
    assert(netc, "socket.create failed")

    local ok, err = xpcall(function()
        assert(socket.config(netc, client_port, true, false), "socket.config failed")
        local succ, online = socket.connect(netc, "127.0.0.1", port)
        assert(succ, "socket.connect failed")
        if not online then
            local evt_ok, param = wait_socket_evt(client_topic, socket.ON_LINE, 5000)
            assert(evt_ok and param == 0, "socket.connect timeout")
        end

        assert(srv:send(payload, "127.0.0.1", client_port), "server send failed")

        local evt_ok, param = wait_socket_evt(client_topic, socket.EVENT, 5000)
        assert(evt_ok and param == 0, "client receive timeout")

        local succ1, len1 = socket.rx(netc, buff, 0, 4)
        assert(succ1 and len1 == 4, "first rx length mismatch")
        assert(buff:toStr(0, len1) == "ABCD", "first rx payload mismatch")
        buff:del()

        local succ2, len2 = socket.rx(netc, buff)
        assert(succ2 and len2 == 0, "udp tail should be discarded")
        buff:del()

        buff = zbuff.create(128)
        assert(srv:send(payload, "127.0.0.1", client_port), "server second send failed")

        local evt_ok2, param2 = wait_socket_evt(client_topic, socket.EVENT, 5000)
        assert(evt_ok2 and param2 == 0, "client second receive timeout")

        local succ3, len3 = socket.rx(netc, buff, 0, 0)
        assert(succ3 and len3 == 0, "zero-limit rx should return 0")

        local succ4, len4 = socket.rx(netc, buff)
        assert(succ4 and len4 == 0, "zero-limit rx should still discard udp tail")
    end, debug.traceback)

    close_client(netc)
    pcall(function()
        srv:close()
    end)

    if not ok then
        error(err)
    end
end

t.udp_limit_suite = udp_limit_suite

return t
