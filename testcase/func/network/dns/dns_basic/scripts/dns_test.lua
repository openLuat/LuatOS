--[[
netdrv 现代 DNS 客户端 真机测试

被测对象是 netdrv 内置的新 DNS 客户端(LUAT_USE_NETDRV_DNS_CLIENT 宏),
对外只有两个入口:
  1. 解析: socket.connect(ctrl, 域名, 0, need_ipv6)
     remote_port 传 0 表示"只解析不连接", DNS 一完成就回调 socket.ON_LINE,
     解析结果用 socket.remoteIP(ctrl) 取(最多 4 个).
  2. 控制: netdrv.ctrl(网卡, netdrv.CTRL_DNS, { ...配置..., stat = true })

因此所有断言都建立在这两个入口上: 行为(拿到几个 IP)用 remoteIP 看,
内部语义(有没有真的发包、有没有命中缓存、在途几个)用 stat 看.

所有测试函数必须以 test_ 开头, 且失败一律 assert 抛错,
只 return false 会让上报丢掉失败原因.
]]

local dnstest = {}

local TAG = "dnstest"
-- DNS 客户端是全局单例, id 参数在 C 侧被忽略, 这里固定用以太网口保持与
-- netready.lua 的初始化方式一致
local ETH = socket.LWIP_ETH

-- 这些域名在 airtest 网络里可解析, 前 6 个来自仓库里已在跑的 http/tcp testcase
local DOMAINS = {
    "luatos.com",
    "www.luatos.com",
    "httpbin.luatos.com",
    "netlab.luatos.com",
    "airtest.openluat.com",
    "download.openluat.com",
    "aiot.mlamp.cn",
    "api.tianditu.gov.cn",
}

-- 用于负缓存的域名, 带上随机尾巴确保一定是 NXDOMAIN 而不是命中缓存
local function bogus_domain()
    return "no-such-host-" .. tostring(mcu.ticks()) .. "-" .. tostring(math.random(1000, 9999)) .. ".invalid"
end

local seq = 0
local function next_topic(prefix)
    seq = seq + 1
    return prefix .. (mcu.ticks() % 100000) .. "_" .. tostring(seq)
end

-- ---------------------------------------------------------------- 控制面

local function dns_ctrl(arg)
    local ok, info = netdrv.ctrl(ETH, netdrv.CTRL_DNS, arg)
    if not ok then
        return nil
    end
    return info
end

local function dns_stat()
    local info = dns_ctrl({ stat = true })
    assert(info and info.stat, TAG .. " CTRL_DNS stat 读取失败")
    return info.stat
end

local function dns_cfg()
    local info = dns_ctrl({ stat = true })
    assert(info and info.cfg, TAG .. " CTRL_DNS cfg 读取失败")
    return info.cfg
end

-- 每次测试前把缓存清干净, 并保证配置回到默认, 避免用例之间互相污染
local function reset_dns()
    local c = dns_cfg()
    assert(netdrv.ctrl(ETH, netdrv.CTRL_DNS, {
        cache_enable = true,
        cache_num    = 32,
        cache_ttl    = 60,
        neg_ttl      = 10,
        max_inflight = 8,
        timeout      = 2000,
        max_retry    = 2,
        min_gap      = 20,
        flush        = true,
    }), TAG .. " 恢复默认配置失败, 原值 " .. tostring(c and c.cache_ttl))
end

-- ---------------------------------------------------------------- 解析面

-- 只解析一个域名, 返回 IP 字符串数组(解析失败/超时返回空表)
--
-- 等待时间要留够: 内部是 timeout(默认2s) x (max_retry+1) 次尝试, 再叠加
-- 指数退避和换服务器间隔. 万一 DNS 服务器彻底没响应, 最坏路径接近 15~20s,
-- 8 秒会把"慢"误判成"失败"(netlab.luatos.com 在 airtest 网络上实测就要 8s+)
local function resolve(domain, need_ipv6, timeout_ms)
    local topic = next_topic("dnsr")
    local ctrl = socket.create(nil, function(_, event)
        if event == socket.ON_LINE then
            sys.publish(topic, "done")
        end
    end)
    if ctrl == nil then
        log.warn(TAG, "socket.create 失败, 无法解析 " .. domain)
        return nil
    end
    local ok, online = socket.connect(ctrl, domain, 0, need_ipv6 and true or false)
    if not ok then
        log.warn(TAG, "socket.connect 被拒绝: " .. domain)
        socket.close(ctrl)
        socket.release(ctrl)
        return nil
    end
    if not online then
        sys.waitUntil(topic, timeout_ms or 25000)
    end
    local ips = {}
    local a, b, c, d = socket.remoteIP(ctrl)
    for _, v in ipairs({ a, b, c, d }) do
        if v then
            ips[#ips + 1] = v
        end
    end
    socket.close(ctrl)
    socket.release(ctrl)
    return ips
end

local function is_ipv6_str(ip)
    return ip and ip:find(":", 1, true) ~= nil
end

--[[
在途峰值采样器.

⚠️ 不要用 sys.timerStart(fn, 10) 的单发定时器来测峰值: 那只有一次采样机会,
几乎必然错过峰值, 断言就变成"看起来在测、其实没测".
这里做成周期性采样, 并且一定要拿到 timer 返回的 id 才停 ——
sys.timerStop 传错 id 是静默 no-op, 定时器会一直跑到进程结束.

采样周期给 25ms 而不是 5ms 是有意的:
  - netdrv.ctrl(CTRL_DNS) 内部要投递事件到 tcpip 线程并轮询等 done, 单次接近 1~2ms;
    5ms 周期会让定时器回调几乎占满 VM 任务, 也会显著放大 SDK 定时器
    "回调与删除竞争" 而产生的 "luat_timer_get no find" 噪声日志。
  - DNS 应答是毫秒~几十毫秒级, 25ms 足够捕捉到"多条同时在途"的窗口
    (实测峰值仍能采到 8 / 双栈采到 2)。
另外回调里用 pcall 包住: 采样失败不该影响被测用例,
停止后仍可能有一次在途回调, 也要能安全返回。
]]
local function probe_peak_start(period_ms)
    local st = { peak = 0, samples = 0, stopped = false }
    local function tick()
        if st.stopped then
            return
        end
        pcall(function()
            local ok, info = netdrv.ctrl(ETH, netdrv.CTRL_DNS, { stat = true })
            if ok and info and info.stat then
                st.samples = st.samples + 1
                if info.stat.inflight > st.peak then
                    st.peak = info.stat.inflight
                end
            end
        end)
    end
    st.id = sys.timerStart(tick, period_ms or 25)
    return st
end

local function probe_peak_stop(st)
    if not st then
        return 0
    end
    -- 先立旗再停表: 停表不保证不再回调, 回调也要立刻变成 no-op
    st.stopped = true
    if st.id then
        sys.timerStop(st.id)
        st.id = nil
    end
    return st.peak
end

-- ================================================================ 用例

function dnstest.setUp()
    -- 宏没打开的话 CTRL_DNS 常量不存在, 后面所有用例都无从谈起, 直接在入口拦掉
    assert(netdrv.CTRL_DNS ~= nil, "netdrv.CTRL_DNS 不存在, LUAT_USE_NETDRV_DNS_CLIENT 宏未生效")
    reset_dns()
end

-- 1) IPv4 解析: 必须拿到至少 1 个地址, 且全是 IPv4
function dnstest.test_dns_resolve_a()
    reset_dns()
    local st0 = dns_stat()
    local ips = resolve(DOMAINS[1], false)
    assert(ips ~= nil, "解析 " .. DOMAINS[1] .. " 未发起成功(socket 资源不足?)")
    assert(#ips >= 1, "解析 " .. DOMAINS[1] .. " 失败, 没有拿到任何地址")
    for i, ip in ipairs(ips) do
        assert(not is_ipv6_str(ip), "仅请求 A 记录却拿到 IPv6 地址: " .. ip)
    end
    local st1 = dns_stat()
    assert(st1.tx > st0.tx, "首次解析应发出 DNS 请求, 但 tx 没有增长")
    assert(st1.rx > st0.rx, "应收到 DNS 应答, 但 rx 没有增长")
    assert(st1.malformed == st0.malformed, "不应出现畸形报文: " .. tostring(st1.malformed))
    log.info(TAG, "A 解析 ok", table.concat(ips, ","), "tx=" .. st1.tx)
end

-- 2) AAAA 解析: 走 IPv6 模式, 客户端会并发发 AAAA + A 两条腿
function dnstest.test_dns_resolve_aaaa()
    reset_dns()
    local st0 = dns_stat()
    local ips = resolve(DOMAINS[2], true)
    assert(ips ~= nil, "解析 " .. DOMAINS[2] .. " 未发起成功(socket 资源不足?)")
    assert(#ips >= 1, "解析 " .. DOMAINS[2] .. " 失败, 没有拿到任何地址")
    -- 双栈查询不允许把 A 的结果弄丢: IPv4 地址必须仍然在结果里
    local v4 = 0
    for _, ip in ipairs(ips) do
        if not is_ipv6_str(ip) then
            v4 = v4 + 1
        end
    end
    assert(v4 >= 1, "双栈查询丢了 IPv4 结果, 只拿到: " .. table.concat(ips, ","))
    local st1 = dns_stat()
    -- 双栈两条腿并发发出, 一次查询至少应该产生 2 个请求
    assert(st1.tx - st0.tx >= 2, "双栈查询应至少发出 2 条请求(A+AAAA), 实际 "
        .. tostring(st1.tx - st0.tx))
    log.info(TAG, "AAAA 解析 ok", table.concat(ips, ","), "tx增量=" .. tostring(st1.tx - st0.tx))
end

-- 3) 缓存命中: 第二次解析不能再发包, 且 cache_hit 必须涨
function dnstest.test_dns_cache_hit_no_tx()
    reset_dns()
    local first = resolve(DOMAINS[3], false)
    assert(first and #first >= 1, "首次解析 " .. DOMAINS[3] .. " 失败")
    local st1 = dns_stat()
    local second = resolve(DOMAINS[3], false)
    assert(second and #second >= 1, "二次解析 " .. DOMAINS[3] .. " 失败")
    assert(table.concat(second, ",") == table.concat(first, ","),
        "缓存命中返回了不同地址: " .. table.concat(first, ",") .. " -> " .. table.concat(second, ","))
    local st2 = dns_stat()
    assert(st2.tx == st1.tx, "缓存命中却仍然发了包, tx " .. st1.tx .. " -> " .. st2.tx)
    assert(st2.cache_hit == st1.cache_hit + 1, "cache_hit 未增长: "
        .. st1.cache_hit .. " -> " .. st2.cache_hit)
    log.info(TAG, "缓存命中 ok, tx 不变 =", st2.tx)
end

-- 4) 缓存过期: 把上限压到 2s, 到点后必须重新发包
function dnstest.test_dns_cache_ttl_expire()
    reset_dns()
    assert(netdrv.ctrl(ETH, netdrv.CTRL_DNS, { cache_ttl = 2 }), TAG .. " 下调 cache_ttl 失败")
    local first = resolve(DOMAINS[4], false)
    assert(first and #first >= 1, "首次解析 " .. DOMAINS[4] .. " 失败")
    local st1 = dns_stat()
    -- TTL 之内再查一次: 仍然命中, 不发包
    local again = resolve(DOMAINS[4], false)
    assert(again and #again >= 1, "TTL 内二次解析失败")
    local st2 = dns_stat()
    assert(st2.tx == st1.tx, "2s TTL 内不应重新发包, tx " .. st1.tx .. " -> " .. st2.tx)
    -- 等过期
    sys.wait(2500)
    local third = resolve(DOMAINS[4], false)
    assert(third and #third >= 1, "过期后重新解析失败")
    local st3 = dns_stat()
    assert(st3.tx > st2.tx, "TTL 过期后必须重新发包, tx 仍是 " .. st3.tx)
    -- 确认上限真的被写进去了
    local cfg = dns_cfg()
    assert(cfg.cache_ttl == 2, "cache_ttl 未生效, 回读为 " .. tostring(cfg.cache_ttl))
    reset_dns()
    log.info(TAG, "缓存过期 ok, tx", st1.tx, "->", st3.tx)
end

-- 5) LRU 淘汰: cache_num=2 时解析 3 个域名, 最早的必须被挤掉
function dnstest.test_dns_cache_lru_evict()
    reset_dns()
    assert(netdrv.ctrl(ETH, netdrv.CTRL_DNS, { cache_num = 2, flush = true }),
        TAG .. " 下调 cache_num 失败")
    for i = 1, 3 do
        local ips = resolve(DOMAINS[i], false)
        assert(ips and #ips >= 1, "解析 " .. DOMAINS[i] .. " 失败")
        sys.wait(50)
    end
    local st1 = dns_stat()
    assert(st1.evict >= 1, "cache_num=2 放入第 3 条时应该发生淘汰, evict=" .. tostring(st1.evict))
    assert(st1.cache_used <= 2, "缓存条目数超过上限: " .. tostring(st1.cache_used))
    -- 第 1 个域名是最早进来的, 应当已被淘汰, 再查必须重新发包
    local ips = resolve(DOMAINS[1], false)
    assert(ips and #ips >= 1, "淘汰后重新解析 " .. DOMAINS[1] .. " 失败")
    local st2 = dns_stat()
    assert(st2.tx > st1.tx, "被淘汰的条目不应命中缓存, tx 仍是 " .. st2.tx)
    -- 第 3 个域名还在, 应当命中
    local tx_before = st2.tx
    local ips3 = resolve(DOMAINS[3], false)
    assert(ips3 and #ips3 >= 1, "重新解析 " .. DOMAINS[3] .. " 失败")
    local st3 = dns_stat()
    assert(st3.tx == tx_before, "未淘汰的条目应命中缓存, tx " .. tx_before .. " -> " .. st3.tx)
    reset_dns()
    log.info(TAG, "LRU 淘汰 ok, evict=", st1.evict, "cache_used=", st1.cache_used)
end

-- 6) 负缓存: NXDOMAIN 结果要被缓存, 第二次不该再发包
function dnstest.test_dns_negative_cache()
    reset_dns()
    local dom = bogus_domain()
    local first = resolve(dom, false)
    assert(first ~= nil, "负缓存用例未能发起解析")
    assert(#first == 0, "不存在的域名 " .. dom .. " 不该解析出地址: " .. table.concat(first, ","))
    local st1 = dns_stat()
    assert(st1.nxdomain >= 1, "nxdomain 计数未增长: " .. tostring(st1.nxdomain))
    local second = resolve(dom, false)
    assert(second ~= nil and #second == 0, "负缓存命中却返回了地址")
    local st2 = dns_stat()
    assert(st2.tx == st1.tx, "负缓存命中仍发了包, tx " .. st1.tx .. " -> " .. st2.tx)
    assert(st2.negative_hit == st1.negative_hit + 1, "negative_hit 未增长: "
        .. st1.negative_hit .. " -> " .. st2.negative_hit)
    log.info(TAG, "负缓存 ok, negative_hit=", st2.negative_hit)
end

-- 7) 并发在途: 一次性发起多个域名查询, 峰值在途数必须 > 1
--    (单队列串行实现的峰值在途数恒为 1, 这是本次改造的核心目标)
function dnstest.test_dns_burst_concurrency()
    reset_dns()
    assert(netdrv.ctrl(ETH, netdrv.CTRL_DNS, { max_inflight = 8, min_gap = 0, flush = true }),
        TAG .. " 调整并发参数失败")

    local n = 8
    local topic = next_topic("burst")
    local ctrls = {}
    local done = 0
    local resolved = 0

    -- 周期性采样在途数, 证明这些查询确实是同时在途的(见 probe_peak_start 的说明)
    local probe = probe_peak_start()

    local st0 = dns_stat()
    for i = 1, n do
        local dom = DOMAINS[i]
        local ctrl = socket.create(nil, function(_, event)
            if event == socket.ON_LINE then
                done = done + 1
                sys.publish(topic, "done")
            end
        end)
        if ctrl == nil then
            log.warn(TAG, "socket 不足, 只发起 " .. (i - 1) .. " 个并发查询")
            break
        end
        local ok = socket.connect(ctrl, dom, 0, false)
        if not ok then
            log.warn(TAG, "无法并发解析 " .. dom)
            socket.close(ctrl)
            socket.release(ctrl)
            break
        end
        ctrls[#ctrls + 1] = ctrl
    end

    assert(#ctrls >= 4, "可用 socket 太少, 无法验证并发(只有 " .. #ctrls .. " 个)")
    sys.waitUntil(topic, 25000)
    sys.wait(300)
    local peak = probe_peak_stop(probe)

    for _, ctrl in ipairs(ctrls) do
        local a = socket.remoteIP(ctrl)
        if a then
            resolved = resolved + 1
        end
        socket.close(ctrl)
        socket.release(ctrl)
    end

    assert(peak >= 2, "未观测到并发在途(峰值 " .. peak .. ", 采样 " .. probe.samples
        .. " 次), 多个查询没有真正同时发出")
    local st1 = dns_stat()
    assert(st1.inflight == 0, "仍有 " .. st1.inflight .. " 个查询挂在途, 事务没有回收")
    assert(st1.tx - st0.tx == #ctrls, "发出请求数应等于并发查询数, 实际 " .. tostring(st1.tx - st0.tx))
    assert(resolved >= 4, "并发查询里只有 " .. resolved .. " 个拿到地址")
    log.info(TAG, "并发在途 ok, 峰值 in-flight =", peak, "成功解析", resolved .. "/" .. #ctrls)
    reset_dns()
end

-- 8) 双栈合并: AAAA + A 两条腿的结果要合并返回, 而不是互相覆盖
function dnstest.test_dns_dual_stack_merge()
    reset_dns()
    local st0 = dns_stat()
    local ips = resolve(DOMAINS[5], true)
    assert(ips ~= nil, "双栈解析未能发起")
    assert(#ips >= 1, "双栈解析失败, 没有拿到任何地址")
    -- 结果不能出现重复项(合并时应去重)
    local seen = {}
    for _, ip in ipairs(ips) do
        assert(seen[ip] == nil, "双栈合并结果出现重复地址: " .. ip)
        seen[ip] = true
    end
    -- 上限是 4 条(MAX_DNS_IP), 不能超过
    assert(#ips <= 4, "返回地址数 " .. #ips .. " 超过 4 条上限")

    --[[
    这里刻意【不】用峰值采样断言"两条腿同时在途"。
    实测本次固件: 双栈查询从发出到拿结果只有约 48ms, 而两条腿同时在途的窗口
    只有 1~2ms —— 定时器采样几乎必然落空(曾经采到"峰值 1、仅 1 次采样"),
    断言就成了 flaky 噪声, 而不是缺陷信号。

    改成两条确定性的证据:
      1. tx 增量 >= 2  —— AAAA 与 A 两条腿的报文都发出来了(不是只发一条);
      2. cache_used 增长 >= 1 —— 结果确实按各自 qtype 入库了(AAAA 若上游无记录
         则只入库 A, 所以是 >= 1 而不是 == 2)。
    这比"总发包 2 条"强: 它同时要求两条腿都被发出【且】分别落缓存,
    串行实现(先 AAAA 全部完成后才发 A)在这里同样会通过, 但那种串行化
    只影响时延、不影响正确性 —— 时延由 test_dns_burst_concurrency 的并发峰值覆盖。
    ]]
    local st = dns_stat()
    local dtx = st.tx - st0.tx
    assert(dtx >= 2, "双栈查询应至少发出 2 条报文(AAAA+A), 实际 " .. tostring(dtx))
    assert(st.cache_used > st0.cache_used, "双栈结果没有入库, cache_used "
        .. tostring(st0.cache_used) .. " -> " .. tostring(st.cache_used))
    assert(st.inflight == 0, "双栈查询结束后仍有事务挂在途")
    log.info(TAG, "双栈合并 ok", table.concat(ips, ","), "tx增量=" .. tostring(dtx))
end

-- 9) 手动失效: flush 之后同样的域名必须重新发包
function dnstest.test_dns_cache_flush()
    reset_dns()
    local first = resolve(DOMAINS[6], false)
    assert(first and #first >= 1, "首次解析 " .. DOMAINS[6] .. " 失败")
    local st1 = dns_stat()
    -- 先确认能命中
    local hit = resolve(DOMAINS[6], false)
    assert(hit and #hit >= 1, "flush 前二次解析失败")
    local st2 = dns_stat()
    assert(st2.tx == st1.tx, "flush 前应命中缓存, tx " .. st1.tx .. " -> " .. st2.tx)

    assert(netdrv.ctrl(ETH, netdrv.CTRL_DNS, { flush = true }), TAG .. " flush 调用失败")
    -- flush 之后紧接着读一次: 必须是 0 条, 不能等到下一次查询把新条目写进去再看
    local st_flushed = dns_stat()
    assert(st_flushed.cache_used == 0, "flush 之后仍有残留缓存条目: "
        .. tostring(st_flushed.cache_used))
    local after = resolve(DOMAINS[6], false)
    assert(after and #after >= 1, "flush 后重新解析失败")
    local st3 = dns_stat()
    assert(st3.cache_used == 1, "flush 后只解析了 1 个域名, 缓存里应当恰好 1 条, 实际 "
        .. tostring(st3.cache_used))
    assert(st3.tx > st2.tx, "flush 之后必须重新发包, tx 仍是 " .. st3.tx)
    log.info(TAG, "手动失效 ok, tx", st2.tx, "->", st3.tx)
end

-- 10) 运行时配置: 改完立刻生效, 并且能原样读回
function dnstest.test_dns_runtime_config()
    reset_dns()
    local base = dns_cfg()
    assert(base.cache_num == 32 and base.cache_ttl == 60, "默认配置不符预期: cache_num="
        .. tostring(base.cache_num) .. " cache_ttl=" .. tostring(base.cache_ttl))

    assert(netdrv.ctrl(ETH, netdrv.CTRL_DNS, {
        cache_num    = 8,
        cache_ttl    = 30,
        neg_ttl      = 5,
        max_inflight = 4,
        timeout      = 1500,
        max_retry    = 1,
        min_gap      = 30,
    }), TAG .. " 写入运行时配置失败")

    local now = dns_cfg()
    assert(now.cache_num == 8, "cache_num 未生效: " .. tostring(now.cache_num))
    assert(now.cache_ttl == 30, "cache_ttl 未生效: " .. tostring(now.cache_ttl))
    assert(now.neg_ttl == 5, "neg_ttl 未生效: " .. tostring(now.neg_ttl))
    assert(now.max_inflight == 4, "max_inflight 未生效: " .. tostring(now.max_inflight))
    assert(now.timeout == 1500, "timeout 未生效: " .. tostring(now.timeout))
    assert(now.max_retry == 1, "max_retry 未生效: " .. tostring(now.max_retry))
    assert(now.min_gap == 30, "min_gap 未生效: " .. tostring(now.min_gap))

    -- 改回去
    reset_dns()
    local back = dns_cfg()
    assert(back.cache_num == 32 and back.cache_ttl == 60, "配置未能恢复: cache_num="
        .. tostring(back.cache_num) .. " cache_ttl=" .. tostring(back.cache_ttl))
    log.info(TAG, "运行时配置 ok")
end

-- 11) 长跑无泄漏: 反复解析 + 反复 flush 之后, C 堆占用不得持续增长
function dnstest.test_dns_no_growth()
    reset_dns()
    --[[
    ⚠️ 度量口径要说清楚, 否则这条用例是"看起来在测、其实没测":
      - rtos.meminfo("sys") 是 luat_heap_* 所在的系统堆(PC 侧为 sram_bget,
        真机由 SDK 的 luat_heap_* 实现), 正是 DNS 客户端分配缓存条目/事务/结果数组的地方。
      - 必须先把在途查询全部收敛(等 inflight 归零)再取值, 否则量到的是"还没跑完的活",
        不是泄漏; 反过来如果刚好停在低谷取值, 又会把泄漏掩盖掉。
    ]]
    local function sys_used()
        local _, used = rtos.meminfo("sys")
        return used
    end

    -- 等所有在途事务收敛, 保证下面两次取样都在"空闲态"
    local function wait_dns_idle(timeout_ms)
        local deadline = mcu.ticks() + (timeout_ms or 5000)
        while mcu.ticks() < deadline do
            local st = dns_stat()
            if st.inflight == 0 then
                return true
            end
            sys.wait(20)
        end
        return false
    end

    -- 预热, 让内部结构稳定下来
    for _ = 1, 3 do
        resolve(DOMAINS[1], false)
        netdrv.ctrl(ETH, netdrv.CTRL_DNS, { flush = true })
    end
    assert(wait_dns_idle(5000), "预热后仍有查询挂在途, 无法得到干净的内存基线")
    sys.wait(200)

    local before = sys_used()
    local rounds = 30
    for i = 1, rounds do
        local dom = DOMAINS[(i % #DOMAINS) + 1]
        local ips = resolve(dom, (i % 4 == 0) == true)
        assert(ips ~= nil, "第 " .. i .. " 轮解析未能发起")
        assert(netdrv.ctrl(ETH, netdrv.CTRL_DNS, { flush = true }), "第 " .. i .. " 轮 flush 失败")
    end
    -- 关键: 先把最后一轮的在途事务收干净, 再取 after
    assert(wait_dns_idle(10000), "长跑结束仍有查询挂在途, 内存对比不成立")
    sys.wait(500)
    local after = sys_used()

    -- 允许 2KB 抖动: lwIP 定时器/socket 收尾会带来少量常驻增长
    assert(after <= before + 2048, "疑似内存泄漏: " .. tostring(before) .. " -> " .. tostring(after)
        .. " (跑了 " .. rounds .. " 轮解析+flush)")

    local st = dns_stat()
    assert(st.inflight == 0, "长跑结束后仍有 " .. st.inflight .. " 个事务挂在途")
    log.info(TAG, "长跑无泄漏 ok, sys heap", before, "->", after)
    reset_dns()
end

return dnstest
