-- netdrv DNS 客户端 (PC 模拟器) 接入测试
--
-- 验证 PC 侧不再走宿主 getaddrinfo, 而是与真机同一份 netdrv DNS 客户端:
--   bsp/pc 的 POSIX 适配层用宿主 UDP socket 收发, 状态机是公共的 luat_netdrv_dns.c。
-- 因此这里的能力断言(tx/rx 增长、缓存命中、负缓存、双栈两条腿)与真机 testcase 语义一致。

local M = {}
local TAG = "dns_pc"
local ETH = socket.LWIP_ETH

local function is_ipv6_str(ip) return ip and ip:find(":", 1, true) ~= nil end

local function stat()
    local ok, info = netdrv.ctrl(ETH, netdrv.CTRL_DNS, { stat = true })
    assert(ok and info and info.stat, TAG .. " 读取 stat 失败")
    return info.stat
end

local function cfg()
    local ok, info = netdrv.ctrl(ETH, netdrv.CTRL_DNS, { stat = true })
    assert(ok and info and info.cfg, TAG .. " 读取 cfg 失败")
    return info.cfg
end

local function reset_dns()
    assert(netdrv.ctrl(ETH, netdrv.CTRL_DNS, {
        cache_enable = true, share = false, cache_num = 32, cache_ttl = 60,
        neg_ttl = 10, max_inflight = 8, timeout = 2000, max_retry = 2, min_gap = 20,
        flush = true,
    }), TAG .. " 恢复默认配置失败")
end

-- 解析一个域名, 返回 remoteIP 列表。
--
-- 刻意不用"等 ON_LINE 回调 + sys.publish"的写法: 本机解析极快, 事件可能在订阅前
-- 就发布了, 等回调会间歇性超时。改成轮询 remoteIP —— 它一旦可读就说明结果已回调
-- 进来, 与时序无关(真机 dns_basic 用回调是因为那条链路耗时足够长)。
local function resolve(domain, need_ipv6, timeout_ms)
    local ctrl = socket.create(nil, function(_, event)
        if event == socket.ON_ERROR then
            log.warn(TAG, "socket error while resolving " .. domain)
        end
    end)
    assert(ctrl, "socket.create 失败")
    assert(socket.connect(ctrl, domain, 0, need_ipv6 and true or false), "socket.connect 被拒绝")
    local deadline = mcu.ticks() + (timeout_ms or 15000)
    local a, b, c, d
    while mcu.ticks() < deadline do
        a, b, c, d = socket.remoteIP(ctrl)
        if a then break end
        sys.wait(20)
    end
    socket.close(ctrl)
    socket.release(ctrl)
    local ips = {}
    for _, v in ipairs({ a, b, c, d }) do
        if v then ips[#ips + 1] = v end
    end
    return ips
end

function M.test_ctrl_dns_available()
    assert(netdrv.CTRL_DNS ~= nil, "netdrv.CTRL_DNS 不存在: 该 BSP 未开启 LUAT_USE_NETDRV_DNS_CLIENT")
    reset_dns()
    local c = cfg()
    -- 默认口径
    assert(c.share == false, "share 默认应为 false, 实际 " .. tostring(c.share))
    assert(c.cache_enable == true, "cache_enable 默认应为 true")
    assert(c.cache_ttl == 60, "cache_ttl 默认应为 60, 实际 " .. tostring(c.cache_ttl))
    assert(c.max_inflight == 8, "max_inflight 默认应为 8")
    log.info(TAG, "CTRL_DNS 可用, cfg ok")
    return true
end

function M.test_resolve_via_netdrv_client()
    reset_dns()
    local st0 = stat()
    local ips = resolve("www.luatos.com", false)
    assert(#ips >= 1, "没有解析到任何地址")
    for _, ip in ipairs(ips) do
        assert(not is_ipv6_str(ip), "仅请求 A 却拿到 IPv6: " .. ip)
    end
    local st1 = stat()
    -- 关键: tx/rx 增长证明真的走了 netdrv DNS 客户端(而不是宿主 getaddrinfo)
    assert(st1.tx > st0.tx, "tx 未增长: 没有走新 DNS 客户端")
    assert(st1.rx > st0.rx, "rx 未增长")
    assert(st1.malformed == 0, "出现畸形报文: " .. tostring(st1.malformed))
    assert(st1.cache_used >= 1, "解析结果未入库")
    log.info(TAG, "解析 ok", ips[1], "tx", st0.tx, "->", st1.tx)
    return true
end

function M.test_cache_hit_no_tx()
    reset_dns()
    local ips1 = resolve("www.luatos.com", false)
    assert(#ips1 >= 1, "首次解析失败")
    local st1 = stat()
    local ips2 = resolve("www.luatos.com", false)
    assert(#ips2 >= 1, "二次解析失败")
    local st2 = stat()
    assert(table.concat(ips1, ",") == table.concat(ips2, ","),
        "缓存命中返回了不同地址: " .. table.concat(ips1, ",") .. " -> " .. table.concat(ips2, ","))
    assert(st2.tx == st1.tx, "缓存命中却又发了包, tx " .. st1.tx .. " -> " .. st2.tx)
    assert(st2.cache_hit > st1.cache_hit, "cache_hit 未增长")
    log.info(TAG, "缓存命中 ok, tx 不变 =", st2.tx)
    return true
end

function M.test_cache_flush_forces_tx()
    reset_dns()
    local ips1 = resolve("www.luatos.com", false)
    assert(#ips1 >= 1, "解析失败")
    local st1 = stat()
    assert(netdrv.ctrl(ETH, netdrv.CTRL_DNS, { flush = true }), "flush 失败")
    assert(stat().cache_used == 0, "flush 后仍有残留条目")
    local ips2 = resolve("www.luatos.com", false)
    assert(#ips2 >= 1, "flush 后解析失败")
    local st2 = stat()
    assert(st2.tx > st1.tx, "flush 后必须重新发包")
    log.info(TAG, "flush ok, tx", st1.tx, "->", st2.tx)
    return true
end

function M.test_dual_stack_legs()
    reset_dns()
    local st0 = stat()
    local ips = resolve("www.luatos.com", true)
    assert(#ips >= 1, "双栈没有拿到地址")
    local st1 = stat()
    local dtx = st1.tx - st0.tx
    assert(dtx >= 2, "双栈应至少发出 2 条报文(AAAA+A), 实际 " .. tostring(dtx))
    assert(st1.cache_used > st0.cache_used, "双栈结果未入库")
    log.info(TAG, "双栈 ok, tx增量=" .. tostring(dtx))
    return true
end

function M.test_negative_cache()
    reset_dns()
    local bad = "no-such-" .. tostring(mcu.ticks()) .. ".invalid"
    resolve(bad, false, 8000)
    local st1 = stat()
    assert(st1.nxdomain >= 1, "nxdomain 计数未增长")
    local tx_before = st1.tx
    resolve(bad, false, 3000)
    local st2 = stat()
    assert(st2.tx == tx_before, "负缓存命中却仍发包, tx " .. tx_before .. " -> " .. st2.tx)
    assert(st2.negative_hit >= 1, "negative_hit 未增长")
    log.info(TAG, "负缓存 ok, negative_hit=" .. tostring(st2.negative_hit))
    return true
end

function M.test_runtime_config_roundtrip()
    reset_dns()
    assert(netdrv.ctrl(ETH, netdrv.CTRL_DNS, {
        share = true, cache_num = 8, cache_ttl = 30, neg_ttl = 5,
        max_inflight = 4, timeout = 1500, max_retry = 1, min_gap = 30,
    }), "写入运行时配置失败")
    local c = cfg()
    assert(c.share == true, "share 未生效")
    assert(c.cache_num == 8, "cache_num 未生效: " .. tostring(c.cache_num))
    assert(c.cache_ttl == 30, "cache_ttl 未生效")
    assert(c.timeout == 1500, "timeout 未生效")
    assert(c.min_gap == 30, "min_gap 未生效")
    reset_dns()
    local back = cfg()
    assert(back.share == false and back.cache_ttl == 60, "配置未能恢复默认")
    log.info(TAG, "运行时配置 ok")
    return true
end

return M
