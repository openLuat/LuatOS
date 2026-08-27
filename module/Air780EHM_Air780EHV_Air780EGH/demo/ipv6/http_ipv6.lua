--[[
@module  http_ipv6
@summary http使用IPv6请求示例
@version 1.0
@date    2026.08.24
@author  拓毅恒
@usage

注意：
测试IPv6地址为 https://mirrors6.tuna.tsinghua.edu.cn/help/centos/ ，如需更换改成顶部url即可

本文件为httpplus优先使用IPv6发起HTTP请求的应用功能模块，核心业务逻辑为：
1、等待ipv6_info发布 IPV6_READY 消息后，通过httpplus.request请求IPv6地址
3、请求成功后打印HTTP响应码和响应体长度，只请求一次即结束

本文件没有对外接口，直接在main.lua中require "http_ipv6"就可以加载运行；
]]

local TAG = "http_ipv6"
local httpplus = require "httpplus"

local function http_ipv6_task()
    -- 等待网络就绪
    sys.waitUntil("IPV6_READY")
    log.info(TAG, "收到 IPV6_READY，准备进行 IPv6 HTTP 请求")

    -- 打开 httpplus 调试日志，方便排查连接/解析过程
    httpplus.debug = true

    -- 请求 IPv6 地址，用于验证 IPv6 外网访问
    log.info(TAG, "发起 HTTP IPv6 请求: https://mirrors6.tuna.tsinghua.edu.cn/help/centos/")
    local code, response = httpplus.request({
        url = "https://mirrors6.tuna.tsinghua.edu.cn/help/centos/",
        try_ipv6 = true,   -- 关键：优先尝试 IPv6 地址
    })
    log.info(TAG, "HTTP 结果 code:", code)
    if code == 200 and response then
        local body = response.body and response.body:query() or ""
        log.info(TAG, "HTTP 请求成功，响应体长度:", #body)
    else
        -- code 为 nil 通常是连接超时/服务器不可达；非 200 是服务器返回了错误状态码
        log.error(TAG, "HTTP IPv6 请求失败 code:", code, "，请确认目标服务器支持 IPv6 且网络可访问")
    end
end

sys.taskInit(http_ipv6_task)
