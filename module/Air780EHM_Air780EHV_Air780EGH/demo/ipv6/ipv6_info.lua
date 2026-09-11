--[[
@module  ipv6_info
@summary 开启IPv6并查询IPv6地址
@version 1.0
@date    2026.08.24
@author  拓毅恒
@usage

注意：
开启IPv6必须在LTE连接前调用mobile.ipv6(true)，否则不会分配IPv6前缀

本文件为IPv6功能的核心模块，负责开启IPv6并查询打印本机地址，核心业务逻辑为：
1、在加载时调用mobile.ipv6(true)开启IPv6
2、轮询等待默认网卡联网就绪
3、通过socket.localIP获取本机地址，其中第4个返回值为IPv6地址，联网成功后打印一次
4、打印完成后广播IPV6_READY消息，通知socket/http/mqtt示例开始运行

本文件没有对外接口，直接在main.lua中require "ipv6_info"就可以加载运行；
]]

local TAG = "ipv6_info"

-- 开启 IPv6 必须在 LTE 连接前设置
mobile.ipv6(true)
log.info(TAG, "IPv6功能开启状态:", mobile.ipv6())  -- nil 查询当前状态，应打印 true

-- 等待 LTE 网络就绪
local function ipv6_info_task()
    log.info(TAG, "等待网络就绪(含IPv6前缀分配)...")
    while not socket.adapter(socket.dft()) do
        sys.wait(100)
    end
    if not socket.adapter(socket.dft()) then
        log.error(TAG, "网络未就绪，无法获取 IPv6 地址，请检查 SIM 卡/信号")
        return
    end
    log.info(TAG, "网络已就绪，开始查询 IPv6 地址")

    -- 联网成功后打印本机地址
    local ipv4, _, _, ipv6 = socket.localIP(socket.dft())
    log.info(TAG, "IPv4 地址:", ipv4)
    if ipv6 and #ipv6 > 0 then
        log.info(TAG, "IPv6 地址:", ipv6)
    else
        log.warn(TAG, "暂未获取到 IPv6 地址，可能 SIM 卡/运营商未开通 IPv6 数据业务")
    end

    sys.publish("IPV6_READY", ipv6)
    log.info(TAG, "已发布 IPV6_READY，其他示例可以开始运行")
end

sys.taskInit(ipv6_info_task)
