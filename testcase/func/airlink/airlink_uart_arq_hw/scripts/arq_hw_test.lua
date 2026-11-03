local tests = {}
function tests.test_uart2_roundtrip()
    log.info("ARQ_HW", "version", rtos.bsp(), _VERSION, "UART2", 2000000)
    uart.setup(2, 2000000, 8, 1)
    airlink.init()
    airlink.config(airlink.CONF_UART_ID, 2)
    airlink.start(airlink.MODE_UART)
    sys.wait(5000)
    local reply, burst, burst_done, burst_error
    local cb = function(id, ok, rtt, data)
        if burst then
            if not burst[id] or not ok or data ~= burst[id] then
                burst_error = "missing/duplicate/corrupt response " .. tostring(id)
            else
                burst[id] = nil
                burst_done = burst_done + 1
            end
        end
        reply = {id=id, ok=ok, rtt=rtt, data=data}
        sys.publish("ARQ_HW_REPLY")
    end
    sys.subscribe("AIRLINK_PING_RESULT", cb)
    local function ping(label, i)
        local payload = string.pack("<I4", i) .. string.rep("\x7d\x7e\x00\xff", 63)
        reply = nil
        local id = airlink.ping(payload, 8000)
        assert(sys.waitUntil("ARQ_HW_REPLY", 8500), "no ping result " .. label)
        assert(reply.id == id and reply.ok and reply.data == payload, "roundtrip mismatch " .. label .. " " .. tostring(reply.rtt))
        log.info("ARQ_HW", label, i, #payload, reply.rtt)
        return reply.rtt, #payload * 2
    end
    local function milliseconds()
        local _, low = mcu.ticks2(1)
        return low
    end
    local elapsed, bytes = 0, 0
    local start = milliseconds()
    for i = 1, 30 do
        local rtt, n = ping("sample", i)
        elapsed = elapsed + rtt
        bytes = bytes + n
    end
    local wall = milliseconds() - start
    log.info("ARQ_HW", "result", "packets", 30, "duplex_bytes", bytes, "sum_rtt_ms", elapsed,
        "wall_ms", wall, "bytes_per_second", math.floor(bytes * 1000 / math.max(1, wall)))
    if airlink.arqState and airlink.arqState().state == 1 then
        local burst_start = milliseconds()
        for batch = 1, 8 do
            burst, burst_done, burst_error = {}, 0, nil
            for n = 1, 16 do
                local payload = string.pack("<I4I4", batch, n) .. string.rep("x\x7d\x7e\xff", 62)
                local id = airlink.ping(payload, 8000)
                assert(id, "burst submit failed")
                burst[id] = payload
            end
            while burst_done < 16 and not burst_error do
                assert(sys.waitUntil("ARQ_HW_REPLY", 8500), "burst timeout")
            end
            assert(not burst_error, burst_error)
            burst = nil
        end
        local burst_ms = milliseconds() - burst_start
        log.info("ARQ_HW", "burst", "packets", 128, "duplex_bytes", 65536, "wall_ms", burst_ms,
            "bytes_per_second", math.floor(65536000 / math.max(1, burst_ms)))
        for i, fault in ipairs({
            {"host_drop_data", 0, false}, {"peer_drop_data", 0, true},
            {"host_duplicate", 2, false}, {"peer_duplicate", 2, true},
            {"host_admission_reject", 3, false}, {"peer_admission_reject", 3, true},
            {"peer_drop_ack", 1, true},
        }) do
            sys.wait(250)
            local before = airlink.arqState()
            assert(airlink.arqFault(fault[2], 3, fault[3]))
            if fault[1] == "peer_drop_ack" then
                sys.wait(500) -- HELLO carries no ACK; the control frame needs retransmission.
                assert(airlink.arqState().retx >= before.retx + 3, "lost ACK was not retried")
            end
            ping(fault[1], 100 + i)
            sys.wait(250)
            if fault[1] == "peer_duplicate" then
                assert(airlink.arqState().dup > before.dup, "duplicate never reached host RX")
            end
            log.info("ARQ_HW", "fault_stats", fault[1], json.encode(airlink.arqState()))
            -- Clear any residual duplicate budget before the next phase.
            assert(airlink.arqFault(fault[2], 0, fault[3]))
        end
        local before_stall = airlink.arqState()
        assert(airlink.arqFault(0, 45, false))
        ping("giveup_retains_pending", 199)
        assert(airlink.arqState().giveup > before_stall.giveup, "stall did not cross giveup threshold")
        sys.wait(500)
        airlink.slave_reboot()
        sys.wait(5000)
        assert(airlink.arqState().state == 1, "peer reboot did not renegotiate")
        ping("peer_reboot", 200)
    else
        log.info("ARQ_HW", "legacy_peer_faults_skipped")
    end
    sys.unsubscribe("AIRLINK_PING_RESULT", cb)
    airlink.statistics()
end
return tests
