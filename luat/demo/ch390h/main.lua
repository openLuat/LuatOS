-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "ch390h"
VERSION = "1.0.0"

--[[
!!! 本demo依赖ulwip库, 2024年的固件肯定不含这个库 !!!
!!! 这个demo主要是调试ch390h的, 实际生产应该用netdrv库的demo!!!!
]]

-- 引入必要的库文件(lua编写), 内部库不需要require
sys = require("sys")
sysplus = require("sysplus")


ch390h = require "ch390h"

function netif_write_out(id, buff)
    -- log.info("ch390h", "out", buff:query():toHex())
    ch390h.send_packet(buff)
end

sys.taskInit(function ()
    sys.wait(100)
    local result = spi.setup(
        0,--串口id
        nil,
        0,--CPHA
        0,--CPOL
        8,--数据宽度
        25600000--,--频率
        -- spi.MSB,--高低位顺序    可选，默认高位在前
        -- spi.master,--主模式     可选，默认主
        -- spi.full--全双工       可选，默认全双工
    )
    print("open",result)
    if result ~= 0 then--返回值为0，表示打开成功
        print("spi open error",result)
        return
    end


    ch390h.software_reset()
    ch390h.default_config()

    local mac = ch390h.mac()
    log.info("MAC地址", (mac:toHex()))
    log.info("vid", (ch390h.vid():toHex()), "pid", (ch390h.pid():toHex()))

    
    -- log.info("通用寄存器", (ch390h.read(0x1F):toHex()))

    log.info("ulwip可用", ulwip)
    local neti = socket.LWIP_ETH
    ulwip.setup(neti, mac, netif_write_out, {zbuff_out=true})
    ulwip.reg(neti)
    -- ulwip.ip(neti, "192.168.1.219", "255.255.255.0", "192.168.1.1")

    local prev_stat = false
    ulwip.link(neti, prev_stat)
    ch390h.disable_rx()
    ch390h.enable_phy()
    ulwip.dhcp(neti, true)
    ulwip.updown(neti, true)
    while 1 do
        local link = ch390h.link()
        -- log.info("网线状态", link, "通用寄存器", (ch390h.read(0x01):toHex()))
        ch390h.write(0x05, (1 <<4) | (1 <<0) | (1 << 3))
        if link ~= prev_stat then
            log.info("ch390h", "网线状态变化", prev_stat, link)
            if link then
                ch390h.enable_rx()
            end
            ulwip.link(neti, link)
            prev_stat = link
        end
        if link then
            -- 读取rx寄存器长度
            local tmp = ch390h.receive_packet()
            if not tmp then
                sys.wait(5)
            else
                -- https://packetor.com/
                -- https://hpd.gasmi.net/
                -- log.info("ch390h", (tmp:toHex()))
                -- log.info("ch390h", "收到数据长度", #tmp)
                ulwip.input(neti, tmp)
            end
        else
            ch390h.enable_phy()
            sys.wait(100)
        end
        
    end
end)


sys.taskInit(function()
    sys.waitUntil("IP_READY")
    while 1 do
        sys.wait(100)
        log.info("http", http.request("GET", "https://httpbin.air32.cn/get", nil, nil, {adapter=socket.LWIP_ETH}).wait())
        log.info("lua", rtos.meminfo())
        log.info("sys", rtos.meminfo("sys"))
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
