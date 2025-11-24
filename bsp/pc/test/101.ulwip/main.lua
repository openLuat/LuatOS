
_G.sys = require("sys")

local function netif_write_out(adapter_index, data)
    log.info("lwip", "发送数据", data:toHex())
end

sys.taskInit(function()
    sys.wait(100)
    -- print(ulwip)

    local adapter_index = socket.LWIP_STA
    local mac = string.fromHex("0CAABBCCDDEE")
    local ret = ulwip.setup(adapter_index, mac, netif_write_out)
    log.info("ulwip.setup", ret)
    if ret then
        log.info("lwip", "添加成功, 设置设备就绪")
        ulwip.updown(adapter_index, true)
        log.info("lwip", "启动dhcp")
        ulwip.dhcp(adapter_index, true)
        sys.wait(1000)
        log.info("lwip", "设置设备已经在线")
        ulwip.link(adapter_index, true)
        while 1 do
            sys.wait(1000)
            log.info("lwip", "linkup", ulwip.link(adapter_index))
            ulwip.input(adapter_index, "123456123456AABBCXCCCDSDD")
        end
    end
end)

sys.run()
