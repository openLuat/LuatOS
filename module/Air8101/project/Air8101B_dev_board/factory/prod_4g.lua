--[[
@module  prod_4g
@summary 产测项 4G_TEST#：Air780ER2 从机（AirLink UART）联网
@usage   4G_TEST#（需插 SIM 卡 + 4G 天线 + VBAT_4G 拨码打开）
@return  string —— 成功回 IP 地址，失败回 "ERROR"
说明
1. 开发板 4G 模组是 Air780ER2 从机，挂 UART1，走 airlink.MODE_UART；
2. 8101 侧没有 mobile 库，读不到 CSQ/ICCID，本项只判"能否经 4G 拿到 IP"；
3. 测完关闭 4G 网卡，避免一直占用；
4. **产测口与 4G 同用一路 UART 时的处理**：
   780ER2 挂在 UART1，而产测口也可能配置成 UART1（config 的 factory.uart_id）。
   这种情况下测试期间把该串口让给模组（解绑产测接收），测完再收回、回包补发，
   期间的过程与结果都打印在日志里（UART0/CH340 那路），产线上看日志即可。
TODO airlink_uart_baud 待真机确认（现按默认 2000000）。
]]

local TIMEOUT_MS = 30000

return function(arg)
    local exnetif = require "exnetif"
    local c = _G.project_config.hw.g4

    -- 产测口与 4G 是否同用一路 UART
    local ft_uart   = (_G.project_config.factory or {}).uart_id
    local same_uart = (ft_uart == c.uart_id)
    local fu        = _G.factory_uart

    if same_uart then
        log.info("prod_4g", "产测口与 4G 同用 UART" .. c.uart_id .. "，临时让出串口给模组")
        log.info("prod_4g", "本次结果请看日志；串口回包在测试结束、串口收回后发出")
        if fu and fu.unbind then fu.unbind() end
        sys.wait(100)
    end

    gpio.setup(c.rst, 1)    -- 4G_RST 释放复位
    sys.wait(100)

    exnetif.set_priority_order({
        {
            airlink_4G = {
                auto_socket_switch = false,
                airlink_type       = airlink.MODE_UART,
                airlink_uart_id    = c.uart_id,   -- UART1
                airlink_uart_baud  = 2000000,
            }
        }
    })

    local got, ip = sys.waitUntil("IP_READY", TIMEOUT_MS)

    -- 收尾：关闭 4G 网卡
    -- airlink 4G 这张网卡的 adapter 是 socket.LWIP_GP_GW（exnetif 在 UART 模式下的默认值）。
    -- 传别的 adapter 只会把该 adapter 状态置成 DISCONNECTED，这张网卡其实没关到。
    pcall(exnetif.close, false, socket.LWIP_GP_GW)
    log.info("prod_4g", "4G 网卡已关闭，结果:", tostring(ip))

    -- 收回产测串口：先等链路静默，把 UART1 上模组残留的字节读掉，
    -- 否则这些数据会被 on_receive 当成产测指令解析，误触发别的测试项。
    if same_uart and fu and fu.bind then
        sys.wait(200)
        for _ = 1, 5 do
            local leftover = uart.read(c.uart_id, 4096)
            if not leftover or leftover == "" then break end
            log.debug("prod_4g", "丢弃模组残留数据", #leftover)
            sys.wait(20)
        end
        fu.bind()
        log.info("prod_4g", "已收回产测串口")
    end

    if not got then
        log.error("prod_4g", TIMEOUT_MS / 1000 .. " 秒内未联网（查 SIM/天线/VBAT_4G/780ER2）")
        return "ERROR"
    end
    log.info("prod_4g", "4G 联网成功，IP:", tostring(ip))
    return ip or "ERROR"
end
