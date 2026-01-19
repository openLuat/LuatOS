local httpdns_test = {}

local httpdns = require("httpdns")

local function assert_ipv4(ip, source)
    assert(ip, string.format("%s未返回有效IP", source))
    local ok = ip:match("^%d+%.%d+%.%d+%.%d+$") ~= nil
    assert(ok, string.format("%s返回值格式异常: %s", source, tostring(ip)))
end

function httpdns_test.test_ali_resolve_air32()
    log.info("httpdns", "使用阿里DNS解析", "air32.cn")
    local ip = httpdns.ali("air32.cn", { timeout = 5000 })
    assert_ipv4(ip, "阿里DNS")
end

function httpdns_test.test_tx_resolve_openluat()
    log.info("httpdns", "使用腾讯DNS解析", "openluat.com")
    local ip = httpdns.tx("openluat.com", { timeout = 5000 })
    assert_ipv4(ip, "腾讯DNS")
end

function httpdns_test.test_invalid_domain_returns_nil()
    local domain = "nonexistent.example.invalid"
    log.info("httpdns", "验证无效域名返回nil", domain)
    local ip_ali = httpdns.ali(domain, { timeout = 3000 })
    assert(ip_ali == nil, string.format("阿里DNS解析无效域名应返回nil, 实际: %s", tostring(ip_ali)))
    local ip_tx = httpdns.tx(domain, { timeout = 3000 })
    assert(ip_tx == nil, string.format("腾讯DNS解析无效域名应返回nil, 实际: %s", tostring(ip_tx)))
end

return httpdns_test
