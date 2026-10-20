--[[
@module  prod_eth
@summary 产测项 ETH_TEST#：CH390H 以太网（SPI0）DHCP 获取 IP
@usage   ETH_TEST#（需插网线 + VBAT_LAN 拨码打开）
@return  string —— 成功回 IP 地址，失败回 "ERROR"
说明
1. 通过 exnetif 把 SPI0 外挂的 CH390H 配成 ETHUSER1 网卡（供电 LAN_EN=53、CS=34、INT=9）；
2. 拿到 IP 即通过，回包直接给 IP；
3. 测完必须收尾：exnetif.close + 拉低供电，否则网卡会一直跑、干扰后续测试
   （参考 Air8300/Air8301 产测的 eth_close 做法）。
]]

local TIMEOUT_MS = 20000

return function(arg)
    local exnetif = require "exnetif"
    local c = _G.project_config.hw.eth

    exnetif.set_priority_order({
        {
            ETHUSER1 = {
                pwrpin = c.en,                            -- LAN_EN
                tp     = netdrv.CH390,
                opts   = { spi = 0, cs = c.cs, irq = c.irq },  -- SPI0 / CS=34 / INT=9
            }
        }
    })

    local got, ip = sys.waitUntil("IP_READY", TIMEOUT_MS)

    -- 无论成败都收尾：关网卡 + 断电
    pcall(exnetif.close, false, socket.LWIP_USER1)
    gpio.setup(c.en, 0)
    log.info("prod_eth", "网口已关闭，结果:", tostring(ip))

    if not got then
        log.error("prod_eth", TIMEOUT_MS / 1000 .. " 秒内未获取到 IP（查网线/对端DHCP/VBAT_LAN）")
        return "ERROR"
    end
    return ip or "ERROR"
end
