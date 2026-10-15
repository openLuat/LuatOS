local t = {}

local suite = {}

-- 全部用例一次跑完。C 侧用假传输层自控时间与网络, 确定性执行。
function suite.test_dns_utest_all()
    assert(netdrv and type(netdrv.dns_utest) == "function",
        "netdrv.dns_utest 不可用(需要 LUAT_USE_UTEST 且开启新 DNS 客户端)")
    assert(netdrv.dns_utest("all") == true, "netdrv.dns_utest(all) 应为 true")
end

-- 报文编码: 标准查询报文字节级正确
function suite.test_dns_utest_query_encode()
    assert(netdrv.dns_utest("query_encode") == true, "query_encode 失败")
end

-- 非法域名必须在入口就被拒绝
function suite.test_dns_utest_query_bad_domain()
    assert(netdrv.dns_utest("query_bad_domain") == true, "query_bad_domain 失败")
end

-- A / AAAA 应答解析
function suite.test_dns_utest_parse_a()
    assert(netdrv.dns_utest("parse_a") == true, "parse_a 失败")
end

function suite.test_dns_utest_parse_aaaa()
    assert(netdrv.dns_utest("parse_aaaa") == true, "parse_aaaa 失败")
end

-- 并发: 8 个不同域名必须同时在途(本次改造的核心目标)
function suite.test_dns_utest_concurrent_inflight()
    assert(netdrv.dns_utest("concurrent_inflight") == true, "并发在途验证失败")
end

-- 双栈: AAAA 与 A 两条腿并发下发
function suite.test_dns_utest_dual_stack_concurrent()
    assert(netdrv.dns_utest("dual_stack_concurrent") == true, "双栈并发验证失败")
end

-- 双栈: 两条腿齐了才回调, 结果合并
function suite.test_dns_utest_dual_stack_merge()
    assert(netdrv.dns_utest("dual_stack_merge") == true, "双栈合并验证失败")
end

-- 缓存命中不得产生任何 DNS 报文
function suite.test_dns_utest_cache_hit()
    assert(netdrv.dns_utest("cache_hit_no_tx") == true, "缓存命中未拦截出包")
end

-- 缓存 TTL 口径: min(记录TTL, 上限); TTL=0 不缓存
function suite.test_dns_utest_cache_ttl_policy()
    assert(netdrv.dns_utest("cache_ttl_policy") == true, "缓存 TTL 策略不符")
end

-- 运行时改配置必须立刻生效
function suite.test_dns_utest_cache_runtime_cfg()
    assert(netdrv.dns_utest("cache_runtime_cfg") == true, "运行时改配置未生效")
end

-- 下调 cache_ttl 不得连带压缩 neg_ttl 负缓存
function suite.test_dns_utest_cache_neg_ttl()
    assert(netdrv.dns_utest("cache_neg_ttl_not_clamped") == true, "负缓存被 cache_ttl 连带压缩")
end

-- 容量上限与 LRU 淘汰
function suite.test_dns_utest_cache_evict()
    assert(netdrv.dns_utest("cache_evict") == true, "LRU 淘汰行为不符")
end

-- NXDOMAIN 负缓存; SERVFAIL 不缓存
function suite.test_dns_utest_negative_cache()
    assert(netdrv.dns_utest("negative_and_servfail") == true, "负缓存策略不符")
end

-- 超时重试 / 指数退避 / 服务器轮转
function suite.test_dns_utest_retry_rotation()
    assert(netdrv.dns_utest("retry_and_rotation") == true, "重试或服务器轮转行为不符")
end

-- 在途上限: 超出排队不丢
function suite.test_dns_utest_max_inflight()
    assert(netdrv.dns_utest("max_inflight_cap") == true, "在途上限行为不符")
end

-- 节奏限速: 允许突发, 限制持续速率
function suite.test_dns_utest_token_bucket()
    assert(netdrv.dns_utest("token_bucket") == true, "节奏限速行为不符")
end

-- 队列推进不得停摆: 只要还有没发出去的事务, 适配层定时器就不能停
-- (对应真机缺陷: inflight 归零 + 令牌桶为空 → 定时器停掉 → 排队查询永久挂起)
function suite.test_dns_utest_queue_drain_gate()
    assert(netdrv.dns_utest("queue_drain_gate") == true, "队列推进门控不正确(可能停摆)")
end

-- 畸形 / 串包 / 伪造 / 截断应答必须被丢弃且不完成事务
function suite.test_dns_utest_malformed()
    assert(netdrv.dns_utest("malformed_rejected") == true, "畸形报文未被正确拒绝")
end

function suite.test_dns_utest_no_question()
    assert(netdrv.dns_utest("no_question") == true, "无 question 的应答未被拒绝")
end

-- 手动失效
function suite.test_dns_utest_flush()
    assert(netdrv.dns_utest("flush") == true, "缓存失效行为不符")
end

-- 大小写不敏感匹配 + 同域名等待者合并
function suite.test_dns_utest_merge()
    assert(netdrv.dns_utest("case_insensitive_and_merge") == true, "等待者合并行为不符")
end

-- 发送失败不消耗重试次数
function suite.test_dns_utest_send_err()
    assert(netdrv.dns_utest("send_err") == true, "发送失败处理不符")
end

-- 释放时挂起请求必须以失败回调, 不得泄漏
function suite.test_dns_utest_deinit()
    assert(netdrv.dns_utest("deinit_flushes") == true, "释放时未回调挂起请求")
end

-- 大量查询后堆内存不得持续增长
function suite.test_dns_utest_no_leak()
    assert(netdrv.dns_utest("no_leak") == true, "疑似内存泄漏")
end

t.dns_suite = suite

return t
