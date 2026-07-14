-- RSA-2048 签名/验签性能测试
-- 依赖：rsa 库，无则跳过
-- 私钥/公钥 PEM 内联嵌入（复用 rsa 单元测试中的测试密钥，非保密）

local M = {}
local helper = require("perf_helper")

local PRIV_PEM = [[-----BEGIN RSA PRIVATE KEY-----
MIIEpAIBAAKCAQEAp0WakShvpE1/28hyZzz0TFiBpN/d6EU2Wkl5lrazTxK/LDdZ
kAQuz6eA+kdPUqSueIpN0X8DT4Or5/0yD/ABvgW2t7A6g2/zQpzv9IoAl2f1Vhnx
dd7iSnhWTeF80lywp4VlHHEVVp7ZCqod59qa9nyp45ycWPwV0VCdX6NwS7chPodC
/Nf4UVbC1/JJ26WPVKqgOuSz0hIX58pnEaU/ntSDuJiLcKdCNUyIHJEzNYGaQVwx
mqBoyolktkTOL04AW/OXlOTP8eZrEZpckrODDaWlLUOt5SARS6qUYJSvuyYry8a0
rGOLbCnoIYVBvu8NX8I5hfeMGnYkEdpx6x/xYwIDAQABAoIBADfwehGDYVqkJFc/
AKtv4g9KJgkaaN7NjrDBE62IagzOqypBVG1qSLFfRi3s/SUZN9POBNpDzLqhwTKz
JTPZQuvmg0WI5Pihzst/KmwwXqRDuvNRd8PAhxL6jXo8J38+SkGrxbWuR8GRG+qK
G7g3Dk3SQQqCjHLh0vYOLKMYSGy5RgfIQyve6yBK1LHeanzgGgcSbawsvCiiDOkb
Y3I8CHasnK/Hxpmx/NzfNfY+r32AVXx4b+sN2YxB7A9OCxgdwYQHxYvKZ1JIiCh+
Mv85wDHT25SJ5NLdP/jHILgGrgpyDN5+9c4fk3rjkoTrTs01wJ4rQfItkQ1Zlr0/
9tub6mECgYEA2e7gerNRv53L0HkY9GS0B7Esi2FiUc/oh4xKRKPm+/ydXcroVbAK
Mz3mCVlRNvkA+68P670s3AKVpeB671R70dCY+MQXTeNaxc0NlhGOKYoerPd9D/GN
CF460AT2SQEWYTdIbin2dxeROEuC79zn1yczxnSwjAvqDwpvpHceP3ECgYEAxH1a
hXk84U5PGKyUuAVMNMaQQll8rcxoFThxrei7iNT6SfVAeHQufCgeW9g1cOL5Vjmk
9Te1caJt2VXaAhq883qZ1ABypQgcfUwLaK6q4BzAIPtYRIpkJstFKaYWqYaVwCGh
QTqcP+ebEJ1BgKgxH4nXjlMUMwf8qzTGmQlO/BMCgYEAzZblG7uIlgyFVnC3Eu7h
SxRgIkjHWMia4yx8b45zfCpORkoBrbw5kyeEmDMzQ3nZ7JS0nz5CUHb7t5UyRA7e
FAwGEz/hgC/H1Svg8j4zb4qF78Q1rdHAqzFBqDXWJP6qnyFo6cwaXzTTYVkS97bc
24J2/HPejO88ad39fhiFZ3ECgYEAvDJgaGU2BYrOwZBTJWqVkhr5g0NY4tJcgq68
W1kFfkqXrAzGglitSWfXpBqTHRuYu5icwe5o0H1F/5t2IvvfLMmp2t/O7vi06OHU
L6DUs7F16GE1KvjuciXRidG19QueFRdg7ywnCiJYaHJmkccGvfF1z7ENMM+el5EG
AwBicZcCgYBdcmz3nmTyGb+BY6yHDNrJh97eSJaP5KOpfs1ZGM4Jx/Pa391q1X9Y
WigaNEpW5eJKzTnyX0GlbEPPhTkBJS4ZwuKRZBvwzmLdoICA+i7gpjwfqDcrdJND
IhEjjWogNyIvepre3eL1HMaJr6TS4j7wZTl7Ha4httCNBkQb0qJeWw==
-----END RSA PRIVATE KEY-----]]

local PUB_PEM = [[-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAp0WakShvpE1/28hyZzz0
TFiBpN/d6EU2Wkl5lrazTxK/LDdZkAQuz6eA+kdPUqSueIpN0X8DT4Or5/0yD/AB
vgW2t7A6g2/zQpzv9IoAl2f1Vhnxdd7iSnhWTeF80lywp4VlHHEVVp7ZCqod59qa
9nyp45ycWPwV0VCdX6NwS7chPodC/Nf4UVbC1/JJ26WPVKqgOuSz0hIX58pnEaU/
ntSDuJiLcKdCNUyIHJEzNYGaQVwxmqBoyolktkTOL04AW/OXlOTP8eZrEZpckrOD
DaWlLUOt5SARS6qUYJSvuyYry8a0rGOLbCnoIYVBvu8NX8I5hfeMGnYkEdpx6x/x
YwIDAQAB
-----END PUBLIC KEY-----]]

local ITERS_SIGN   = 5
local ITERS_VERIFY = 5

local function skip_if_no_rsa()
    if not rsa then
        log.warn("perf_rsa", "rsa 库不可用，跳过 RSA 性能测试")
        return true
    end
    return false
end

-- 预计算一次签名，供验签测试复用
local _sig_cache = nil
local _hash_cache = nil

local function get_sign_cache()
    if _sig_cache then return _hash_cache, _sig_cache end
    _hash_cache = crypto.sha256("LuatOS perf benchmark payload"):fromHex()
    _sig_cache  = rsa.sign(PRIV_PEM, rsa.MD_SHA256, _hash_cache, "")
    return _hash_cache, _sig_cache
end

function M.test_perf_rsa_sign()
    if skip_if_no_rsa() then return end
    helper.section("RSA-2048 SHA256 签名")
    local hash = crypto.sha256("LuatOS perf benchmark payload"):fromHex()
    assert(hash and #hash == 32, "SHA256 应为 32 字节")
    helper.measure("RSA-2048 sign", function()
        local sig = rsa.sign(PRIV_PEM, rsa.MD_SHA256, hash, "")
        assert(sig and #sig > 0, "RSA 签名失败")
    end, ITERS_SIGN)
    -- 缓存以备验签测试使用
    get_sign_cache()
end

function M.test_perf_rsa_verify()
    if skip_if_no_rsa() then return end
    helper.section("RSA-2048 SHA256 验签")
    local hash, sig = get_sign_cache()
    assert(sig and #sig > 0, "签名缓存无效，请先运行 test_perf_rsa_sign")
    helper.measure("RSA-2048 verify", function()
        local ok = rsa.verify(PUB_PEM, rsa.MD_SHA256, hash, sig)
        assert(ok == true, "RSA 验签失败")
    end, ITERS_VERIFY)
end

return M
